// The quota glance: four rings, dashes for missing pairs, dimmed for stale.
import SwiftUI

struct GlanceView: View {
    @EnvironmentObject var model: PulseModel

    var body: some View {
        VStack(spacing: 6) {
            if !model.reachable && !model.demoMode {
                Label("Mac unreachable", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Button("Try demo mode") { model.demoMode = true }
                    .font(.footnote)
                    .buttonStyle(.bordered)
            }
            let t = model.tokens
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 8) {
                ring("SESSION", t?.claudeSession, t?.fetchedAt, Theme.claude)
                ring("WEEK", t?.claudeWeek, t?.fetchedAt, Theme.claude)
                ring(t?.claudeModelWeekLabel ?? "MODEL · WEEK",
                     t?.claudeModelWeek, t?.fetchedAt, Theme.claude)
                ring("CODEX · WEEK", t?.codexWeek, t?.fetchedAt, Theme.codex)
            }
        }
        .navigationTitle("AgentTap")
    }

    @ViewBuilder
    private func ring(_ label: String, _ pair: QuotaPair?,
                      _ fetchedAt: Date?, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Gauge(value: min(max(pair?.pct ?? 0, 0), 100), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text(pair.map { "\(Int($0.pct.rounded()))" } ?? "–")
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(pair == nil ? Theme.muted.opacity(0.4) : tint)
            .opacity(pair?.stale == true ? 0.5 : 1)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(pairFooter(pair, fetchedAt))
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted.opacity(0.8))
        }
    }

    private func pairFooter(_ pair: QuotaPair?, _ fetchedAt: Date?) -> String {
        guard let pair, let fetchedAt else { return "–" }
        let reset = resetText(pair, fetchedAt: fetchedAt)
        return pair.stale ? "STALE · \(reset)" : reset
    }
}
