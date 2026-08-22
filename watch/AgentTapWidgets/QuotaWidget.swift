// Complication: the tighter of Claude's two weekly quotas as a gauge.
// Fetches directly (GETs are unauthenticated); staleness is worn openly as
// the age of the last successful fetch.
import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let pct: Double?
    let label: String
    let stale: Bool
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: .now, pct: 42, label: "WEEK", stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        Task { completion(await fetch()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        Task {
            let entry = await fetch()
            completion(Timeline(entries: [entry],
                                policy: .after(.now + 15 * 60)))
        }
    }

    private func fetch() async -> QuotaEntry {
        let defaults = UserDefaults.standard
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: cfg)
        let base = defaults.string(forKey: "serverBase").flatMap {
            $0.isEmpty ? nil : $0
        } ?? GeneratedDefaults.serverBase
        if let url = URL(string: base)?.appendingPathComponent("api/tokens"),
           let (data, resp) = try? await session.data(from: url),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let snap = TokensSnapshot.parse(data) {
            let week = snap.claudeWeek
            let model = snap.claudeModelWeek
            let tightest = [week, model].compactMap { $0 }.max { $0.pct < $1.pct }
            defaults.set(tightest?.pct ?? -1, forKey: "lastQuotaPct")
            defaults.set(Date().timeIntervalSince1970, forKey: "lastQuotaAt")
            return QuotaEntry(date: .now, pct: tightest?.pct,
                              label: "WEEK", stale: tightest?.stale ?? false)
        }
        // Unreachable: show the last known value, honestly aged.
        let last = defaults.double(forKey: "lastQuotaPct")
        let at = defaults.double(forKey: "lastQuotaAt")
        let aged = at > 0 && Date().timeIntervalSince1970 - at < 6 * 3600
        return QuotaEntry(date: .now, pct: (aged && last >= 0) ? last : nil,
                          label: "WEEK", stale: true)
    }
}

struct QuotaWidgetView: View {
    var entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack {
                gauge
                VStack(alignment: .leading) {
                    Text("AgentTap").font(.headline)
                    Text(entry.pct.map {
                        "Claude \(Int($0.rounded()))%\(entry.stale ? " · stale" : "")"
                    } ?? "no data")
                        .font(.footnote)
                }
            }
        case .accessoryInline:
            Text(entry.pct.map { "VP \(Int($0.rounded()))%" } ?? "VP –")
        default:
            gauge
        }
    }

    private var gauge: some View {
        Gauge(value: min(max(entry.pct ?? 0, 0), 100), in: 0...100) {
            Text("VP")
        } currentValueLabel: {
            Text(entry.pct.map { "\(Int($0.rounded()))" } ?? "–")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .opacity(entry.stale ? 0.6 : 1)
    }
}

@main
struct AgentTapWidgets: WidgetBundle {
    var body: some Widget {
        QuotaWidget()
    }
}

struct QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentTapQuota", provider: QuotaProvider()) {
            QuotaWidgetView(entry: $0)
        }
        .configurationDisplayName("Claude quota")
        .description("Tightest weekly quota from your Mac's tokenserver.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
