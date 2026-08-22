// Demo mode: the whole app running on recorded, self-consistent data —
// no server, no network. Exists so anyone (including an App Store reviewer)
// can experience the glance, the agents page, and a full Needs You decision
// without a VibePulse tokenserver. Values are plausible, never real.
import Foundation

enum DemoData {
    static func tokens(now: Date = Date()) -> TokensSnapshot {
        TokensSnapshot(
            claudeSession: QuotaPair(pct: 42, resetMin: 173, stale: false),
            claudeWeek: QuotaPair(pct: 61, resetMin: 6221, stale: false),
            claudeModelWeek: QuotaPair(pct: 28, resetMin: 6221, stale: false),
            claudeModelWeekLabel: "OPUS · WEEK",
            codexSession: nil,
            codexWeek: QuotaPair(pct: 17, resetMin: 4380, stale: false),
            fetchedAt: now)
    }

    static func agents(now: Date = Date()) -> AgentStatus {
        AgentStatus(
            seq: 1,
            claude: [
                AgentJob(taskID: "demo1", eventID: "a", state: "working",
                         project: "shop-backend", activity: "editing",
                         model: "OPUS", updatedMS: 2100),
                AgentJob(taskID: "demo2", eventID: "b", state: "waiting",
                         project: "ios-app", activity: "waiting_input",
                         model: "SONNET", updatedMS: 41000),
            ],
            claudeActive: 2,
            codex: [
                AgentJob(taskID: "demo3", eventID: "c", state: "working",
                         project: "data-pipeline", activity: "testing",
                         model: nil, updatedMS: 800),
            ],
            codexActive: 1,
            pending: nil)
    }

    /// A self-consistent pending question: its digest is recomputed from its
    /// own canonical view, so the exact same verification path runs as for
    /// real decisions.
    static func pending(now: Date = Date()) -> Pending {
        var p = Pending(
            requestID: "DemoRequestAAAAAAAAAAAA", provider: "claude",
            kind: "question", project: "shop-backend", expiresInMS: 118_000,
            holdMS: 120_000, optionsTotal: 2, marked: true, tool: nil,
            prompt: "Deploy the fix to staging?",
            title: "Yes, deploy",
            subtitle: "Runs the staging pipeline",
            canApprove: true, viewSHA256: "", fetchedAt: now)
        p.viewSHA256 = p.recomputedDigest
        return p
    }
}
