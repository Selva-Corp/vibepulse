// Bonjour discovery of tokenservers on this network. The tokenserver
// announces _vibepulse._tcp named after its host, so the instance name maps
// directly to http://<name>.local:8737 — no resolution round-trip needed.
import Foundation
import Network

@MainActor
final class ServerDiscovery: ObservableObject {
    struct Found: Identifiable, Equatable {
        let name: String
        var id: String { name }
        var url: String { "http://\(name).local:8737" }
    }

    @Published var servers: [Found] = []
    private var browser: NWBrowser?

    func start() {
        stop()
        let browser = NWBrowser(
            for: .bonjour(type: "_vibepulse._tcp", domain: nil),
            using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Found? in
                guard case let .service(name, _, _, _) = result.endpoint
                else { return nil }
                return Found(name: name)
            }.sorted { $0.name < $1.name }
            Task { @MainActor in self?.servers = found }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Resolves a discovered service to a concrete IP URL. Physical watches
    /// routinely hang on `.local` hostname lookups (the -1001 lesson), so
    /// the tap stores an address that needs no resolver at all. Falls back
    /// to the `.local` form if the connect probe fails.
    nonisolated static func resolve(_ found: Found) async -> String {
        let endpoint = NWEndpoint.service(
            name: found.name, type: "_vibepulse._tcp", domain: "local.",
            interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if done { return false }
                done = true
                return true
            }
        }
        let once = Once()
        let url: String? = await withCheckedContinuation { cont in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard once.claim() else { return }
                    if case let .hostPort(host, port)? =
                        connection.currentPath?.remoteEndpoint {
                        var h = "\(host)"
                        if let pct = h.firstIndex(of: "%") {
                            h = String(h[..<pct])
                        }
                        let formatted = h.contains(":") ? "[\(h)]" : h
                        cont.resume(returning:
                            "http://\(formatted):\(port.rawValue)")
                    } else {
                        cont.resume(returning: nil)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    guard once.claim() else { return }
                    cont.resume(returning: nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                guard once.claim() else { return }
                cont.resume(returning: nil)
                connection.cancel()
            }
        }
        return url ?? found.url
    }
}
