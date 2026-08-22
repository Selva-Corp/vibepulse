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

    private var client: VibePulseClient
    // Runtime pairing (keychain) wins over a key baked in at build time.
    private var signer = Signer(deviceKeyHex: KeyStore.load() ?? DeviceKey.hex)
    private var answered = AnsweredRing()
    private var pollTask: Task<Void, Never>?

    var serverBase: String {
        get { storedBase.isEmpty ? GeneratedDefaults.serverBase : storedBase }
        set {
            storedBase = newValue
            client = VibePulseClient(base: newValue)
        }
    }
    var canAnswer: Bool { demoMode || signer.hasKey }
    var pairedViaCode: Bool { KeyStore.load() != nil }

    /// Redeem a pairing code; on success the key lands in the keychain and
    /// answering turns on immediately.
    func pair(code: String) async -> String {
        let result = await client.claimPairing(code: code)
        guard let key = result.key else { return result.reason }
        KeyStore.save(key)
        signer = Signer(deviceKeyHex: key)
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
                    self.apply(status)
                } else {
                    self.reachable = false
                }
                if Date().timeIntervalSince(lastTokens) >= 30 {
                    if let snap = await self.client.fetchTokens() {
                        self.tokens = snap
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    lastTokens = Date()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
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
        let result = await client.answer(p, verdict: verdict, signer: signer)
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
