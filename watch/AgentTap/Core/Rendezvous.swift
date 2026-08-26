// The pairing code doubles as server discovery: while it lives, the
// computer parks its LAN address at the hosted relay under a hash of the
// code, encrypted with a code-derived key. Mirrors the stdlib scheme in
// tools/tokenserver/pairing.py exactly (HMAC-SHA256 keystream + tag) and
// is pinned against a shared vector in the tests. This exists because
// third-party watch apps cannot browse Bonjour on real watchOS.
import CryptoKit
import Foundation

enum Rendezvous {
    static let relayBase = "https://agenttap-push-relay.jgselva2012.workers.dev"
    private static let salt = "agenttap-rendezvous-v1"

    static func codeID(_ code: String) -> String {
        Data(SHA256.hash(data: Data("\(salt)|id|\(code)".utf8)))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func kmat(_ code: String) -> SymmetricKey {
        SymmetricKey(data: Data(SHA256.hash(
            data: Data("\(salt)|\(code)".utf8))))
    }

    private static func keystream(_ key: SymmetricKey, _ length: Int) -> Data {
        var out = Data()
        var counter: UInt32 = 0
        while out.count < length {
            var msg = Data("ks".utf8)
            withUnsafeBytes(of: counter.bigEndian) { msg.append(contentsOf: $0) }
            out.append(Data(HMAC<SHA256>.authenticationCode(
                for: msg, using: key)))
            counter += 1
        }
        return out.prefix(length)
    }

    static func decrypt(code: String, payload: String) -> Data? {
        guard let raw = RelayCrypto.b64urlDecode(payload),
              raw.count > 32 else { return nil }
        let ct = raw.prefix(raw.count - 32)
        let tag = raw.suffix(32)
        let key = kmat(code)
        let expected = Data(HMAC<SHA256>.authenticationCode(
            for: Data("tag".utf8) + ct, using: key))
        guard expected == Data(tag) else { return nil }
        let ks = keystream(key, ct.count)
        return Data(zip(ct, ks).map { $0 ^ $1 })
    }

    struct Announcement {
        let hosts: [String]
        let port: Int
    }

    /// Fetch + decrypt the computer's announcement for this code, or nil.
    static func fetch(code: String) async -> Announcement? {
        guard let url = URL(string: relayBase + "/rendezvous/"
                            + codeID(code)) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any],
              let payload = obj["payload"] as? String,
              let plain = decrypt(code: code, payload: payload),
              let inner = (try? JSONSerialization.jsonObject(with: plain))
                as? [String: Any],
              let hosts = inner["hosts"] as? [String], !hosts.isEmpty,
              let port = inner["port"] as? Int else { return nil }
        return Announcement(hosts: hosts, port: port)
    }
}
