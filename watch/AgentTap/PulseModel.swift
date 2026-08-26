// App state: ScenePhase-driven polling (agent-status 1 Hz, tokens 30 s),
// Needs You presentation rules, answer/panic flow.
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class PulseModel: ObservableObject {
    @AppStorage("serverBase") private var storedBase: String = ""
    @AppStorage("demoMode") var demoMode: Bool = false {
        didSet { restartPolling() }
    }
    @Published var tokens: TokensSnapshot?
    @Published var agents: AgentStatus?
    @Published var presented: Pending?
    @Published var lastAnswer: AnswerResult?
    @Published var reachable = true
    @Published var netError: String?
    /// True while data is arriving over the encrypted relay instead of LAN.
    @Published var viaRelay = false

    private var client: VibePulseClient
    // Runtime pairing (keychain) wins over a key baked in at build time.
    private var signer = Signer(deviceKeyHex: KeyStore.load() ?? DeviceKey.hex)
    private var answered = AnsweredRing()
    private var pollTask: Task<Void, Never>?
    private var relay: RelayTransport?
    private var lanFailures = 0

    private func makeRelay() -> RelayTransport? {
        guard let config = KeyStore.loadRelay() else { return nil }
        return RelayTransport(config: config, deviceKeyHex: signingKeyHex)
    }

    private func relayOrMake() -> RelayTransport? {
        if relay == nil { relay = makeRelay() }
        return relay
    }

    var relayConfigured: Bool { KeyStore.loadRelay() != nil }

    var serverConfigured: Bool { !serverBase.isEmpty }

    /// Tap-to-select from discovery: resolve to a raw IP first so physical
    /// watches never depend on .local lookups.
    func selectServer(_ found: ServerDiscovery.Found) async {
        serverBase = await ServerDiscovery.resolve(found)
        lanFailures = 0
        restartPolling()
    }

    var serverBase: String {
        get { storedBase.isEmpty ? GeneratedDefaults.serverBase : storedBase }
        set {
            let cleaned = VibePulseClient.normalize(newValue)
            storedBase = cleaned
            client = VibePulseClient(base: cleaned)
        }
    }
    var canAnswer: Bool { demoMode || signer.hasKey }
    var signingKeyHex: String { KeyStore.load() ?? DeviceKey.hex }
    var pairedViaCode: Bool { KeyStore.load() != nil }

    /// Redeem a pairing code; on success the key lands in the keychain and
    /// answering turns on immediately.
    func pair(code: String) async -> String {
        // The code carries the computer's address (watchOS cannot browse
        // Bonjour): find the server first, then claim on it directly.
        if let found = await Rendezvous.fetch(code: code) {
            for host in found.hosts {
                let formatted = host.contains(":") ? "[\(host)]" : host
                let base = "http://\(formatted):\(found.port)"
                let probe = VibePulseClient(base: base)
                let attempt = await probe.claimPairing(code: code)
                if let key = attempt.key {
                    serverBase = base
                    return finishPairing(key: key, relay: attempt.relay)
                }
                if attempt.reason != "unreachable" {
                    return attempt.reason  // reached a server; real verdict
                }
            }
        }
        let result = await client.claimPairing(code: code)
        guard let key = result.key else { return result.reason }
        return finishPairing(key: key, relay: result.relay)
    }

    private func finishPairing(key: String,
                               relay relayConfig: RelayConfig?) -> String {
        KeyStore.save(key)
        if let relayConfig {
            KeyStore.saveRelay(relayConfig)
        }
        signer = Signer(deviceKeyHex: key)
        relay = makeRelay()
        lanFailures = 0
        restartPolling()
        objectWillChange.send()
        return "ok"
    }

    func unpair() {
        KeyStore.clear()
        signer = Signer(deviceKeyHex: DeviceKey.hex)
        objectWillChange.send()
    }

    init() {
        let base = UserDefaults.standard.string(forKey: "serverBase") ?? ""
        client = VibePulseClient(base: base.isEmpty ? GeneratedDefaults.serverBase : base)
    }

    private var isActive = false

    private func restartPolling() {
        setActive(isActive)
    }

    func setActive(_ active: Bool) {
        isActive = active
        pollTask?.cancel()
        pollTask = nil
        guard active else { return }
        if demoMode {
            pollTask = Task { [weak self] in
                guard let self else { return }
                self.tokens = DemoData.tokens()
                self.agents = DemoData.agents()
                self.reachable = true
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled, self.demoMode else { return }
                let p = DemoData.pending()
                if !self.answered.contains(p.requestID) {
                    self.presented = p
                }
            }
            return
        }
        pollTask = Task { [weak self] in
            var lastTokens = Date.distantPast
            while !Task.isCancelled {
                guard let self else { return }
                if let status = await self.client.fetchAgentStatus() {
                    self.reachable = true
                    self.viaRelay = false
                    self.lanFailures = 0
                    self.apply(status)
                } else {
                    self.lanFailures += 1
                    self.netError = self.client.lastError
                    // Two straight LAN misses and a paired relay: go remote.
                    if self.lanFailures >= 2,
                       let relay = self.relayOrMake() {
                        await self.pollRelayOnce(relay)
                    } else {
                        self.reachable = false
                    }
                }
                if Date().timeIntervalSince(lastTokens) >= 30 {
                    if let snap = await self.client.fetchTokens() {
                        self.tokens = snap
                        WidgetCenter.shared.reloadAllTimelines()
                    } else if let snap = await self.fetchTokensViaRelay() {
                        // The numbers mailbox refreshes at most every 300 s
                        // server-side; the 30 s check just picks changes up.
                        self.tokens = snap
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    lastTokens = Date()
                }
                // Relay polls pace at 5 s like the panel; LAN at 1 Hz.
                try? await Task.sleep(nanoseconds:
                    self.viaRelay ? 5_000_000_000 : 1_000_000_000)
            }
        }
    }

    private func fetchTokensViaRelay() async -> TokensSnapshot? {
        guard let numbers = KeyStore.loadRelay()?.numbersURL,
              let url = URL(string: numbers + "/api/tokens") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return TokensSnapshot.parse(data)
    }

    private func pollRelayOnce(_ relay: RelayTransport) async {
        var sawAnything = false
        if let status = await relay.fetchStatus() {
            agents = status
            sawAnything = true
        }
        if let pending = await relay.fetchNext() {
            sawAnything = true
            if presented?.requestID == pending.requestID {
                presented = pending
            } else if !answered.contains(pending.requestID),
                      pending.expiresInMS >= 3000 {
                presented = pending
            }
        } else if presented?.relayChallenge != nil {
            // Nothing pending relay-side anymore (answered elsewhere or
            // expired) — drop a relay-presented card.
            presented = nil
        }
        if sawAnything {
            reachable = true
            viaRelay = true
        } else {
            reachable = false
            viaRelay = false
        }
    }

    private func apply(_ status: AgentStatus) {
        agents = status
        guard let p = status.pending else {
            presented = nil
            return
        }
        if answered.contains(p.requestID) { return }
        // Firmware rules: refuse a digest mismatch outright; don't raise the
        // screen for a nearly-expired item (TK_NEEDS_YOU_MIN_SHOW_MS = 3000).
        guard p.digestValid else { return }
        if presented?.requestID == p.requestID {
            presented = p  // refresh countdown source
        } else if p.expiresInMS >= 3000 {
            presented = p
        }
    }

    func answer(_ verdict: Verdict) async {
        guard let p = presented else { return }
        if demoMode {
            lastAnswer = AnswerResult(ok: true, reason: "ok (demo)")
            answered.mark(p.requestID)
            presented = nil
            return
        }
        let result: AnswerResult
        if p.relayChallenge != nil, let relay = relayOrMake() {
            let ok = await relay.postVerdict(p, verdict: verdict)
            result = AnswerResult(ok: ok,
                                  reason: ok ? "ok (relay)" : "relay failed")
        } else {
            result = await client.answer(p, verdict: verdict, signer: signer)
        }
        lastAnswer = result
        answered.mark(p.requestID)
        presented = nil
    }

    func panic() async {
        lastAnswer = await client.panic(signer: signer)
        if let p = presented {
            answered.mark(p.requestID)
            presented = nil
        }
    }

    func dismissPending() {
        if let p = presented { answered.mark(p.requestID) }
        presented = nil
    }
}
