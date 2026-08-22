// The takeover: countdown ring, then APPROVE only when the server said the
// item is approvable, DENY only for approvals (questions keep their options
// in the terminal), LEAVE IT always. A private item (no detail) is tap-to-
// hand-back, exactly like the panel.
import SwiftUI

struct NeedsYouSheet: View {
    @EnvironmentObject var model: PulseModel
    let pending: Pending
    @State private var confirmPanic = false
    @State private var sending = false

    private var accent: Color {
        pending.provider == "codex" ? Theme.codex : Theme.claude
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = pending.expiryDate.timeIntervalSince(context.date)
            ScrollView {
                VStack(spacing: 8) {
                    header(remaining: remaining)
                    if pending.isPrivate {
                        Text("Something is waiting")
                            .font(.headline)
                        Text("Details stay on the computer")
                            .font(.footnote).foregroundStyle(Theme.muted)
                        Button("HAND TO TERMINAL") { send(.leaveIt) }
                            .buttonStyle(.bordered)
                    } else {
                        detail
                        buttons
                    }
                }
            }
            .onChange(of: remaining <= 0) { _, expired in
                if expired { model.dismissPending() }
            }
        }
        .confirmationDialog("Deny everything pending?",
                            isPresented: $confirmPanic) {
            Button("DENY ALL", role: .destructive) {
                Task { await model.panic() }
            }
        }
        .disabled(sending)
    }

    @ViewBuilder
    private func header(remaining: TimeInterval) -> some View {
        HStack {
            Circle().fill(accent).frame(width: 8, height: 8)
            Text(pending.project ?? "unknown")
                .font(.footnote.weight(.semibold))
            Spacer()
            Gauge(value: max(0, min(1, remaining * 1000 / Double(pending.holdMS)))) {
                EmptyView()
            } currentValueLabel: {
                Text("\(max(0, Int(remaining.rounded(.up))))")
                    .font(.system(size: 11, design: .rounded))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(accent)
            .frame(width: 32, height: 32)
        }
        .onLongPressGesture(minimumDuration: 1.5) { confirmPanic = true }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pending.isQuestion
                 ? "QUESTION" : "APPROVAL · \(pending.tool ?? "?")")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            if let prompt = pending.prompt {
                Text(prompt).font(.footnote)
            }
            if let title = pending.title {
                Text(title).font(.footnote.weight(.semibold))
            }
            if let subtitle = pending.subtitle {
                Text(subtitle).font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            if pending.isQuestion, let n = pending.optionsTotal, n > 1 {
                Text("\(n - 1) more option\(n > 2 ? "s" : "") in terminal")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 6) {
            if pending.canApprove && model.canAnswer {
                Button { send(.approve) } label: {
                    Text("APPROVE").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
            if !pending.isQuestion && model.canAnswer {
                Button { send(.deny) } label: {
                    Text("DENY").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            Button { send(.leaveIt) } label: {
                Text("LEAVE IT").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.muted)
        }
    }

    private func send(_ verdict: Verdict) {
        sending = true
        Task {
            await model.answer(verdict)
            sending = false
        }
    }
}
