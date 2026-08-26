import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: PulseModel
    @State private var base = ""
    @State private var code = ""
    @State private var pairStatus = ""
    @State private var pairing = false
    @StateObject private var discovery = ServerDiscovery()

    var body: some View {
        Form {
            Section("Server") {
                ForEach(discovery.servers) { found in
                    Button {
                        Task {
                            await model.selectServer(found)
                            base = model.serverBase
                        }
                    } label: {
                        Label(found.name, systemImage:
                              model.serverBase == found.url
                              ? "checkmark.circle.fill" : "desktopcomputer")
                            .font(.footnote)
                    }
                }
                TextField("http://mac.local:8737", text: $base)
                    .onSubmit { model.serverBase = base }
            }
            Section {
                Label(pairingLabel, systemImage: model.canAnswer
                      ? "checkmark.seal" : "eye")
                    .font(.footnote)
                TextField("6-digit code", text: $code)
                    .font(.system(.body, design: .monospaced))
                Button(pairing ? "Pairing…" : "Pair") {
                    pairing = true
                    Task {
                        pairStatus = await model.pair(code: code)
                        if pairStatus == "ok" { code = "" }
                        pairing = false
                    }
                }
                .disabled(pairing || code.filter(\.isNumber).count != 6)
                if !pairStatus.isEmpty {
                    Text(pairStatus == "ok" ? "Paired — answering is on"
                         : pairHint(pairStatus))
                        .font(.system(size: 11))
                        .foregroundStyle(pairStatus == "ok"
                                         ? .green : Theme.muted)
                }
                if model.pairedViaCode {
                    Button("Unpair", role: .destructive) {
                        model.unpair()
                        pairStatus = ""
                    }
                }
            } header: {
                Text("Pairing")
            } footer: {
                Text("On your computer, run:\npython3 tools/vibepulse_setup.py pair")
                    .font(.system(size: 10, design: .monospaced))
            }
            Section {
                Toggle("Demo mode", isOn: $model.demoMode)
                    .font(.footnote)
            } footer: {
                Text("Recorded sample data — no computer needed. Turn off to use your own.")
                    .font(.system(size: 10))
            }
            if let last = model.lastAnswer {
                Section {
                    Text("Last answer: \(last.reason)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            base = model.serverBase
            discovery.start()
        }
        .onDisappear { discovery.stop() }
    }

    private var pairingLabel: String {
        if model.pairedViaCode { return "Paired (code)" }
        if model.canAnswer { return "Paired (built-in key)" }
        return "Display-only"
    }

    private func pairHint(_ reason: String) -> String {
        switch reason {
        case "not armed":
            return "No code is active — run the pair command, then enter the fresh code within 60 s"
        case "bad code":
            return "Wrong code — check the digits on your computer"
        case "unreachable":
            return "Can't reach the server — check the Server address"
        default:
            return reason
        }
    }
}
