// GET /api/tokens (contract v:2). A quota pair is valid only when both Pct
// and ResetMin are present — otherwise it renders as dashes, never zeros.
import Foundation

struct QuotaPair: Equatable {
    var pct: Double
    var resetMin: Int
    var stale: Bool
}

struct TokensSnapshot: Equatable {
    var claudeSession: QuotaPair?
    var claudeWeek: QuotaPair?
    var claudeModelWeek: QuotaPair?
    var claudeModelWeekLabel: String?
    var codexSession: QuotaPair?
    var codexWeek: QuotaPair?
    var fetchedAt: Date

    private static func num(_ d: [String: Any], _ k: String) -> Double? {
        guard let n = d[k] as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }
    private static func boolVal(_ d: [String: Any], _ k: String) -> Bool {
        guard let n = d[k] as? NSNumber,
              CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }
    private static func pair(_ d: [String: Any], _ base: String,
                             staleKey: String?) -> QuotaPair? {
        guard let pct = num(d, base + "Pct"),
              let reset = num(d, base + "ResetMin") else { return nil }
        let stale = staleKey.map { boolVal(d, $0) } ?? false
        return QuotaPair(pct: pct, resetMin: Int(reset), stale: stale)
    }

    static func parse(_ data: Data, fetchedAt: Date = Date()) -> TokensSnapshot? {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let d = any as? [String: Any],
              (d["v"] as? NSNumber)?.intValue == 2,
              d["error"] == nil else { return nil }
        return TokensSnapshot(
            claudeSession: pair(d, "claudeSession", staleKey: nil),
            claudeWeek: pair(d, "claudeWeek", staleKey: "claudeWeekStale"),
            claudeModelWeek: pair(d, "claudeModelWeek", staleKey: "claudeModelWeekStale"),
            claudeModelWeekLabel: d["claudeModelWeekLabel"] as? String,
            codexSession: pair(d, "codexSession", staleKey: nil),
            codexWeek: pair(d, "codexWeek", staleKey: "codexWeekStale"),
            fetchedAt: fetchedAt)
    }
}
