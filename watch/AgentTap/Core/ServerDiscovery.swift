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
}
