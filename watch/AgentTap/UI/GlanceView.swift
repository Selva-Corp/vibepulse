// The quota glance: four rings, dashes for missing pairs, dimmed for stale.
import SwiftUI

struct GlanceView: View {
    @EnvironmentObject var model: PulseModel
    @StateObject private var discovery = ServerDiscovery()

    var body: some View {
        VStack(spacing: 6) {
            if model.viaRelay {
                Label("Via relay", systemImage: "cloud")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }
            if !model.reachable && !model.demoMode {
                if model.serverConfigured {
                    Label("Mac unreachable", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    if let err = model.netError {
                        Text(err)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("On your computer, run the setup — then enter the 6-digit code under Settings → Pairing. It connects everything.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                ForEach(discovery.servers) { found in
                    Button {
                        Task { await model.selectServer(found) }
                    } label: {
                        Label(found.name, systemImage: "desktopcomputer")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                }
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
        .onAppear { if !model.reachable { discovery.start() } }
        .onDisappear { discovery.stop() }
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
