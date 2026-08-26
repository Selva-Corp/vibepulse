// HTTP client for the interaction relay Worker — panel role. Mirrors the
// firmware client's hygiene: bearer auth, Cache-Control: no-store required,
// 204 means empty, byte-identical retries (a re-encrypted retry would 409),
// and a strictly increasing publicationId gate on status.
import Foundation

struct RelayConfig: Codable, Equatable {
    let url: String
    let mailbox: String
    let panelToken: String
}

final class RelayTransport {
    private let config: RelayConfig
    private let keys: RelayCrypto.Keys
    private let session: URLSession
    private var lastPublicationId: UInt64
    private var verdictCache: [String: Data] = [:]  // requestId -> body

    init?(config: RelayConfig, deviceKeyHex: String,
          lastPublicationId: UInt64 = 0) {
        guard let deviceKey = RelayCrypto.decodeDeviceKey(hex: deviceKeyHex)
        else { return nil }
        self.config = config
        self.keys = RelayCrypto.deriveKeys(deviceKey: deviceKey,
                                           mailbox: config.mailbox)
        self.lastPublicationId = lastPublicationId
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    private func request(_ method: String, _ route: String,
                         body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: URL(
            string: config.url + "/v1/mailboxes/\(config.mailbox)" + route)!)
        req.httpMethod = method
        req.setValue("Bearer \(config.panelToken)",
                     forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json",
                         forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func noStore(_ resp: URLResponse?) -> Bool {
        ((resp as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Cache-Control") ?? "")
            .lowercased().contains("no-store")
    }

    /// GET requests/next → the decrypted pending decision, or nil.
    func fetchNext(now: Date = Date()) async -> Pending? {
        guard let (data, resp) = try? await session.data(
            for: request("GET", "/requests/next")),
              let http = resp as? HTTPURLResponse, noStore(resp)
        else { return nil }
        if http.statusCode == 204 { return nil }
        guard http.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any],
              let requestId = obj["requestId"] as? String,
              let wrapperExpiryMs = obj["expiresAtMs"] as? Double,
              let envObj = obj["envelope"] as? [String: Any],
              let envelope = RelayCrypto.parseEnvelope(
                  envObj, expectCiphertext: 2064),
              let frame = RelayCrypto.open(
                  envelope, key: keys.requestAead,
                  aad: RelayCrypto.requestAAD(mailbox: config.mailbox,
                                              requestId: requestId)),
              let req = RelayCrypto.decodeRequestFrame(
                  frame, requestId: requestId)
        else { return nil }
        let innerExpiryMs = Double(req.expiresAt) * 1000
        let expiresInMs = min(innerExpiryMs, wrapperExpiryMs)
            - now.timeIntervalSince1970 * 1000
        guard expiresInMs > 0 else { return nil }
        guard var pending = Pending.fromViewBytes(
            req.viewBytes, viewSha256: req.viewSha256,
            expiresInMS: Int(expiresInMs), fetchedAt: now) else { return nil }
        pending.relayChallenge = req.challenge
        return pending
    }

    /// POST the verdict. LAN verdict names map: leave_it → terminal.
    func postVerdict(_ pending: Pending, verdict: Verdict) async -> Bool {
        guard let challenge = pending.relayChallenge,
              let viewSha = RelayCrypto.decodeDeviceKey(hex: pending.viewSHA256)
        else { return false }
        let relayVerdict: String
        switch verdict {
        case .approve: relayVerdict = "approve"
        case .deny: relayVerdict = "deny"
        case .leaveIt: relayVerdict = "terminal"
        }
        let body: Data
        if let cached = verdictCache[pending.requestID] {
            body = cached  // byte-identical retry, never re-encrypt
        } else {
            guard let built = RelayCrypto.sealedVerdict(
                keys: keys, mailbox: config.mailbox,
                requestId: pending.requestID, challenge: challenge,
                viewSha256: viewSha, verdict: relayVerdict)
            else { return false }
            verdictCache[pending.requestID] = built
            body = built
        }
        guard let (_, resp) = try? await session.data(
            for: request("POST", "/requests/\(pending.requestID)/verdict",
                         body: body)),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200 || http.statusCode == 201
    }

    /// Test hook: the exact envelope postVerdict would send (and caches).
    func debugSealedVerdict(_ pending: Pending,
                            verdict: Verdict) -> Data? {
        guard let challenge = pending.relayChallenge,
              let viewSha = RelayCrypto.decodeDeviceKey(hex: pending.viewSHA256)
        else { return nil }
        let name = verdict == .approve ? "approve"
            : verdict == .deny ? "deny" : "terminal"
        let built = RelayCrypto.sealedVerdict(
            keys: keys, mailbox: config.mailbox,
            requestId: pending.requestID, challenge: challenge,
            viewSha256: viewSha, verdict: name)
        if let built { verdictCache[pending.requestID] = built }
        return built
    }

    /// GET status → decrypted agent snapshot (no pending ever rides here).
    func fetchStatus(now: Date = Date()) async -> AgentStatus? {
        guard let (data, resp) = try? await session.data(
            for: request("GET", "/status")),
              let http = resp as? HTTPURLResponse, noStore(resp),
              http.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any],
              let envObj = obj["envelope"] as? [String: Any],
              let envelope = RelayCrypto.parseEnvelope(
                  envObj, expectCiphertext: 2832),
              let frame = RelayCrypto.open(
                  envelope, key: keys.statusAead,
                  aad: RelayCrypto.statusAAD(mailbox: config.mailbox)),
              let status = RelayCrypto.decodeStatusFrame(frame)
        else { return nil }
        guard status.publicationId > lastPublicationId,
              Double(status.expiresAt) > now.timeIntervalSince1970
        else { return nil }
        lastPublicationId = status.publicationId
        return AgentStatus.parse(status.statusBytes)
    }
}
