// Remote-notification plumbing: ask permission, collect the APNs token,
// hand it to the tokenserver signed with the device key (possession proof —
// junk tokens can't be planted). The notification only wakes the human;
// verdicts still happen in the app against the digest-verified card.
import Foundation
import CryptoKit
import UserNotifications
import WatchKit

final class PushRegistrar: NSObject, WKApplicationDelegate,
                           UNUserNotificationCenterDelegate {
    static let shared = PushRegistrar()
    var serverBase: (() -> String)?
    var deviceKey: (() -> String)?
    /// True only while the app is on screen — watchOS keeps an app
    /// "frontmost" for minutes after wrist-down, and willPresent is
    /// consulted through that whole window.
    var appIsActive = false

    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                WKApplication.shared().registerForRemoteNotifications()
            }
        }
    }

    func didRegisterForRemoteNotifications(withDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        Task { await register(tokenHex: hex) }
    }

    private func register(tokenHex: String) async {
        guard let base = serverBase?(),
              let key = deviceKey?(), key.count == 64,
              let url = URL(string: VibePulseClient.normalize(base))?
                  .appendingPathComponent("api/push/register")
        else { return }
        let ts = Int(Date().timeIntervalSince1970)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data("push|register|\(tokenHex)|\(ts)".utf8),
            using: SymmetricKey(data: Data(key.utf8)))
            .map { String(format: "%02x", $0) }.joined()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(
            "{\"token\":\"\(tokenHex)\",\"ts\":\(ts),\"hmac\":\"\(mac)\"}"
                .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    // On screen: the full-screen card is the alert (with its own haptic) —
    // a banner on top would be noise. Any other state — wrist down, watch
    // face, another app, frontmost-but-dark — gets banner + sound (the buzz).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        appIsActive ? [] : [.banner, .sound]
    }
}
