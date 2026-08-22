// Live agent rows, ranked waiting > error > working > done > idle.
import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var model: PulseModel

    var body: some View {
        List {
            section("CLAUDE", model.agents?.claude ?? [],
                    model.agents?.claudeActive ?? 0, Theme.claude)
            section("CODEX", model.agents?.codex ?? [],
                    model.agents?.codexActive ?? 0, Theme.codex)
        }
        .navigationTitle("Agents")
    }

    @ViewBuilder
    private func section(_ name: String, _ jobs: [AgentJob],
                         _ active: Int, _ tint: Color) -> some View {
        Section {
            if jobs.isEmpty {
                Text("idle").foregroundStyle(Theme.muted).font(.footnote)
            }
            ForEach(jobs) { job in
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.project).font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(job.activity ?? job.state)
                            .font(.system(size: 11))
                            .foregroundStyle(job.state == "waiting"
                                             ? tint : Theme.muted)
                    }
                    Spacer()
                    if let m = job.model {
                        Text(m).font(.system(size: 9))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        } header: {
            Text(active > 0 ? "\(name) · \(active)" : name)
        }
    }
}
