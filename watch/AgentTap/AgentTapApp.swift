import SwiftUI
import WatchKit

@main
struct AgentTapApp: App {
    @WKApplicationDelegateAdaptor(PushRegistrar.self)
    private var pushRegistrar
    @StateObject private var model = PulseModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TabView {
                    GlanceView()
                    AgentsView()
                }
                .tabViewStyle(.verticalPage)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .environmentObject(model)
            .sheet(item: $model.presented) { pending in
                NeedsYouSheet(pending: pending)
                    .environmentObject(model)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
            if phase == .active {
                pushRegistrar.serverBase = { model.serverBase }
                pushRegistrar.deviceKey = { model.signingKeyHex }
            }
        }
    }
}
