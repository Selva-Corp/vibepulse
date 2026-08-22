// The pending Needs You decision: tolerant decoding plus the canonical-view
// digest recompute. Twin of components/app_tokens/agent_status_parse.c
// (:690-733): the client refuses any pending whose recomputed digest differs
// from the published one — "I approved THIS screen" must be literally true.
import Foundation

struct Pending: Equatable, Identifiable {
    var requestID: String
    var provider: String
    var kind: String            // "question" | "approval"
    var project: String?
    var expiresInMS: Int
    var holdMS: Int
    var optionsTotal: Int?
    var marked: Bool?
    var tool: String?
    var prompt: String?
    var title: String?
    var subtitle: String?
    var canApprove: Bool
    var viewSHA256: String
    var fetchedAt: Date

    var id: String { requestID }
    var isQuestion: Bool { kind == "question" }
    /// title == nil is the private screen: no buttons, a tap hands it back.
    var isPrivate: Bool { title == nil && prompt == nil }
    var expiryDate: Date { fetchedAt.addingTimeInterval(Double(expiresInMS) / 1000) }

    // MARK: strict JSON field readers (bool and number never conflate)

    private static func str(_ d: [String: Any], _ k: String) -> String? {
        d[k] as? String
    }
    private static func int(_ d: [String: Any], _ k: String) -> Int? {
        guard let n = d[k] as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.intValue
    }
    private static func bool(_ d: [String: Any], _ k: String) -> Bool? {
        guard let n = d[k] as? NSNumber,
              CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    private static let hex64 = try! NSRegularExpression(pattern: "^[0-9a-f]{64}$")

    /// Malformed or unknown-shaped pending means "nothing to answer" —
    /// never an error, and never a reason to drop the agent rows.
    static func parse(_ any: Any?, fetchedAt: Date = Date()) -> Pending? {
        guard let d = any as? [String: Any],
              let requestID = str(d, "request_id"), !requestID.isEmpty,
              let provider = str(d, "provider"),
              provider == "claude" || provider == "codex",
              let kind = str(d, "kind"),
              kind == "question" || kind == "approval",
              let expires = int(d, "expires_in_ms"), expires >= 0,
              let hold = int(d, "hold_ms"), hold > 0,
              let canApprove = bool(d, "can_approve"),
              let digest = str(d, "view_sha256"),
              hex64.firstMatch(in: digest, range: NSRange(digest.startIndex..., in: digest)) != nil
        else { return nil }
        return Pending(
            requestID: requestID, provider: provider, kind: kind,
            project: str(d, "project"), expiresInMS: expires, holdMS: hold,
            optionsTotal: int(d, "options_total"), marked: bool(d, "marked"),
            tool: str(d, "tool"), prompt: str(d, "prompt"),
            title: str(d, "title"), subtitle: str(d, "subtitle"),
            canApprove: canApprove, viewSHA256: digest, fetchedAt: fetchedAt)
    }

    // MARK: canonical view (must byte-match Python json.dumps(sort_keys=True,
    // separators=(",",":"), ensure_ascii=False) with null keys omitted)

    static func jsonEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 2)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)  // non-ASCII stays raw
                }
            }
        }
        return out
    }

    /// Fixed ASCII-sorted key order; expires_in_ms and view_sha256 excluded.
    var canonicalView: String {
        var parts: [String] = []
        func put(_ key: String, _ value: String?) {
            if let v = value { parts.append("\"\(key)\":\"\(Pending.jsonEscape(v))\"") }
        }
        func put(_ key: String, _ value: Int?) {
            if let v = value { parts.append("\"\(key)\":\(v)") }
        }
        func put(_ key: String, _ value: Bool?) {
            if let v = value { parts.append("\"\(key)\":\(v ? "true" : "false")") }
        }
        put("can_approve", canApprove)
        put("hold_ms", holdMS)
        put("kind", kind)
        put("marked", marked)
        put("options_total", optionsTotal)
        put("project", project)
        put("prompt", prompt)
        put("provider", provider)
        put("request_id", requestID)
        put("subtitle", subtitle)
        put("title", title)
        put("tool", tool)
        return "{" + parts.joined(separator: ",") + "}"
    }

    var recomputedDigest: String { sha256Hex(canonicalView) }
    var digestValid: Bool { recomputedDigest == viewSHA256 }
}
