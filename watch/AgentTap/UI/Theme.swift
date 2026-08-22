// Locked provider accents — same invariants as the panel: Claude #D97757,
// Codex #6F78FF, muted #9298A2. Never fabricate data; absence renders dashed.
import SwiftUI

enum Theme {
    static let claude = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let codex = Color(red: 0x6F / 255, green: 0x78 / 255, blue: 0xFF / 255)
    static let muted = Color(red: 0x92 / 255, green: 0x98 / 255, blue: 0xA2 / 255)
}

func resetText(_ pair: QuotaPair, fetchedAt: Date, now: Date = Date()) -> String {
    let elapsedMin = Int(now.timeIntervalSince(fetchedAt) / 60)
    let m = max(0, pair.resetMin - elapsedMin)
    if m >= 1440 { return "\(m / 1440)d \((m % 1440) / 60)h" }
    if m >= 60 { return "\(m / 60)h \(m % 60)m" }
    return "\(m)m"
}
