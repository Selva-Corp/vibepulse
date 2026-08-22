// GET /api/agent-status (contract v:2, polled at 1 Hz while frontmost).
// Unknown root keys are tolerated; a malformed `pending` means "nothing to
// answer" and must never take the agent rows down with it.
import Foundation

struct AgentJob: Equatable, Identifiable {
    var taskID: String
    var eventID: String
    var state: String       // idle|working|waiting|done|error|unknown
    var project: String
    var activity: String?
    var model: String?
    var updatedMS: Int

    var id: String { taskID + eventID }

    /// Panel row ranking: waiting > error > working > done > idle.
    var rank: Int {
        switch state {
        case "waiting": return 0
        case "error": return 1
        case "working": return 2
        case "done": return 3
        default: return 4
        }
    }
}

struct AgentStatus: Equatable {
    var seq: Int
    var claude: [AgentJob]
    var claudeActive: Int
    var codex: [AgentJob]
    var codexActive: Int
    var pending: Pending?

    private static func jobs(_ any: Any?) -> (rows: [AgentJob], active: Int) {
        guard let d = any as? [String: Any] else { return ([], 0) }
        let active = (d["active_count"] as? NSNumber)?.intValue ?? 0
        var rows: [AgentJob] = []
        for item in (d["jobs"] as? [Any]) ?? [] {
            guard let j = item as? [String: Any],
                  let taskID = j["task_id"] as? String,
                  let eventID = j["event_id"] as? String,
                  let state = j["state"] as? String,
                  let project = j["project"] as? String,
                  let updated = (j["updated_ms"] as? NSNumber)?.intValue
            else { continue }
            rows.append(AgentJob(
                taskID: taskID, eventID: eventID, state: state,
                project: project, activity: j["activity"] as? String,
                model: j["model"] as? String, updatedMS: updated))
        }
        rows.sort { ($0.rank, -$0.updatedMS) < ($1.rank, -$1.updatedMS) }
        return (rows, active)
    }

    static func parse(_ data: Data, fetchedAt: Date = Date()) -> AgentStatus? {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let d = any as? [String: Any],
              (d["v"] as? NSNumber)?.intValue == 2,
              let seq = (d["seq"] as? NSNumber)?.intValue,
              let agents = d["agents"] as? [String: Any] else { return nil }
        let claude = jobs(agents["claude"])
        let codex = jobs(agents["codex"])
        return AgentStatus(
            seq: seq,
            claude: claude.rows, claudeActive: claude.active,
            codex: codex.rows, codexActive: codex.active,
            pending: Pending.parse(d["pending"], fetchedAt: fetchedAt))
    }
}
