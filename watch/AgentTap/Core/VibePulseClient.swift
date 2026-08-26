// HTTP client for the tokenserver. Plain HTTP on the LAN, HTTP/1.0 server
// (no keep-alive); 2.5 s request timeout like the firmware.
import Foundation

struct AnswerResult {
    var ok: Bool
    var reason: String
}

final class VibePulseClient {
    var baseURL: URL
    private let session: URLSession
    /// Last transport failure, for the glance diagnostic line.
    private(set) var lastError: String?

    static func normalize(_ base: String) -> String {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty && !s.contains("://") { s = "http://" + s }
        return s
    }

    init(base: String) {
        self.baseURL = URL(string: VibePulseClient.normalize(base))
            ?? URL(string: "http://localhost:8737")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2.5
        cfg.timeoutIntervalForResource = 5
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    func fetchTokens() async -> TokensSnapshot? {
        guard let (data, resp) = try? await session.data(
                from: baseURL.appendingPathComponent("api/tokens")),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return TokensSnapshot.parse(data)
    }

    func fetchAgentStatus() async -> AgentStatus? {
        do {
            let (data, resp) = try await session.data(
                from: baseURL.appendingPathComponent("api/agent-status"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                lastError = "http \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
                return nil
            }
            lastError = nil
            return AgentStatus.parse(data)
        } catch {
            let u = error as? URLError
            lastError = "\(u?.code.rawValue ?? (error as NSError).code) "
                + (u.map { String(describing: $0.code) }
                   ?? (error as NSError).domain)
            return nil
        }
    }

    /// Signs against the RECOMPUTED digest — never the published one — so the
    /// verdict is bound to exactly what this screen rendered.
    func answer(_ pending: Pending, verdict: Verdict, signer: Signer) async -> AnswerResult {
        guard pending.digestValid else {
            return AnswerResult(ok: false, reason: "view digest mismatch")
        }
        var req = URLRequest(url: baseURL
            .appendingPathComponent("api/interaction/\(pending.requestID)"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = signer.answerBody(
            provider: pending.provider, requestID: pending.requestID,
            viewSHA256: pending.recomputedDigest, verdict: verdict,
            ts: Int(Date().timeIntervalSince1970))
        return await post(req)
    }

    /// Redeem a 6-digit pairing code for the device key. The code was armed
    /// on the computer via `vibepulse_setup.py pair` and is single-use.
    func claimPairing(code: String) async
        -> (key: String?, relay: RelayConfig?, reason: String) {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/pair/claim"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{\"code\":\"\(code.filter(\.isNumber))\"}".utf8)
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return (nil, nil, "unreachable")
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if http.statusCode == 200,
           let key = body?["device_key"] as? String, key.count == 64 {
            var relay: RelayConfig? = nil
            if let r = body?["relay"] as? [String: Any],
               let url = r["url"] as? String,
               let mailbox = r["mailbox"] as? String,
               let token = r["panel_token"] as? String, token.count == 43 {
                relay = RelayConfig(url: url, mailbox: mailbox,
                                    panelToken: token)
            }
            return (key, relay, "ok")
        }
        return (nil, nil, body?["reason"] as? String ?? "http \(http.statusCode)")
    }

    func panic(signer: Signer) async -> AnswerResult {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/panic"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = signer.panicBody(ts: Int(Date().timeIntervalSince1970))
        return await post(req)
    }

    private func post(_ req: URLRequest) async -> AnswerResult {
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return AnswerResult(ok: false, reason: "unreachable")
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let ok = (body?["ok"] as? NSNumber)?.boolValue ?? (http.statusCode == 200)
        let reason = body?["reason"] as? String ?? "http \(http.statusCode)"
        return AnswerResult(ok: ok, reason: reason)
    }
}
