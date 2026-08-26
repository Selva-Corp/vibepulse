// The interaction-relay wire format, ported byte-for-byte from
// tools/tokenserver/interaction_relay_crypto.py and pinned against
// test-vectors/interaction-relay-v1.json + agent-status-relay-v1.json.
//
// Everything here is exacting on purpose: canonical JSON is enforced by
// re-serialization on both the Worker and the Mac, every integer is
// big-endian, base64url is unpadded-canonical, and the verdict MAC keys on
// the DECODED 32-byte device key while the LAN v2 HMAC keys on the 64 hex
// characters. Divergence anywhere is a silent rejection.
import CryptoKit
import Foundation

enum RelayCrypto {
    static let protocolInfo = "vibepulse-ir/v1"
    static let saltInput = "VibePulse interaction relay v1"
    static let requestFrameBytes = 2048
    static let verdictFrameBytes = 1024
    static let statusFrameBytes = 2816
    static let statusHeaderBytes = 50
    static let maxViewBytes = 640
    static let maxStatusBytes = 2560
    static let nonceBytes = 12

    struct Keys {
        let requestAead: SymmetricKey
        let verdictAead: SymmetricKey
        let verdictMac: SymmetricKey
        let statusAead: SymmetricKey
    }

    /// 64 lowercase hex chars → 32 bytes (device keys AND view digests —
    /// the LAN pending stores its digest as hex, never base64url).
    static func decodeDeviceKey(hex: String) -> Data? {
        let h = hex.lowercased()
        guard h.count == 64 else { return nil }
        var out = Data(capacity: 32)
        var idx = h.startIndex
        for _ in 0..<32 {
            let next = h.index(idx, offsetBy: 2)
            guard let b = UInt8(h[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        return out
    }

    static func deriveKeys(deviceKey: Data, mailbox: String) -> Keys {
        let salt = Data(SHA256.hash(data: Data(saltInput.utf8)))
        func derive(_ label: String) -> SymmetricKey {
            let info = Data("\(protocolInfo)|\(mailbox)|\(label)".utf8)
            return HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: deviceKey),
                salt: salt, info: info, outputByteCount: 32)
        }
        return Keys(requestAead: derive("mac-to-panel-aead"),
                    verdictAead: derive("panel-to-mac-aead"),
                    verdictMac: derive("panel-verdict-mac"),
                    statusAead: derive("mac-to-panel-status-aead"))
    }

    // MARK: base64url, unpadded canonical

    static func b64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func b64urlDecode(_ s: String) -> Data? {
        guard !s.contains("="), s.count % 4 != 1 else { return nil }
        var b = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let data = Data(base64Encoded: b) else { return nil }
        // canonical: re-encode must round-trip
        guard b64urlEncode(data) == s else { return nil }
        return data
    }

    // MARK: envelope — canonical {"ciphertext":..,"nonce":..,"v":1}

    static func envelopeJSON(ciphertext: Data, nonce: Data) -> Data {
        Data(("{\"ciphertext\":\"" + b64urlEncode(ciphertext) +
              "\",\"nonce\":\"" + b64urlEncode(nonce) + "\",\"v\":1}").utf8)
    }

    struct Envelope {
        let ciphertext: Data
        let nonce: Data
    }

    /// Parses an envelope OBJECT (already JSON-decoded by the transport)
    /// with the same strictness the Mac applies: exact keys, canonical
    /// base64url, exact ciphertext length.
    static func parseEnvelope(_ object: [String: Any],
                              expectCiphertext: Int) -> Envelope? {
        guard Set(object.keys) == ["ciphertext", "nonce", "v"],
              let v = object["v"] as? Int, v == 1,
              let cs = object["ciphertext"] as? String,
              let ns = object["nonce"] as? String,
              let ciphertext = b64urlDecode(cs),
              let nonce = b64urlDecode(ns),
              nonce.count == nonceBytes,
              ciphertext.count == expectCiphertext else { return nil }
        return Envelope(ciphertext: ciphertext, nonce: nonce)
    }

    static func open(_ envelope: Envelope, key: SymmetricKey,
                     aad: String) -> Data? {
        guard envelope.ciphertext.count > 16 else { return nil }
        let ct = envelope.ciphertext.prefix(envelope.ciphertext.count - 16)
        let tag = envelope.ciphertext.suffix(16)
        guard let n = try? AES.GCM.Nonce(data: envelope.nonce),
              let box = try? AES.GCM.SealedBox(
                  nonce: n, ciphertext: ct, tag: tag) else { return nil }
        return try? AES.GCM.open(box, using: key,
                                 authenticating: Data(aad.utf8))
    }

    static func seal(_ plaintext: Data, key: SymmetricKey, aad: String,
                     nonce: Data) -> Data? {
        guard let n = try? AES.GCM.Nonce(data: nonce),
              let box = try? AES.GCM.seal(
                  plaintext, using: key, nonce: n,
                  authenticating: Data(aad.utf8)) else { return nil }
        return box.ciphertext + box.tag
    }

    static func requestAAD(mailbox: String, requestId: String) -> String {
        "\(protocolInfo)|\(mailbox)|\(requestId)|request"
    }
    static func verdictAAD(mailbox: String, requestId: String) -> String {
        "\(protocolInfo)|\(mailbox)|\(requestId)|verdict"
    }
    static func statusAAD(mailbox: String) -> String {
        "\(protocolInfo)|\(mailbox)|status"
    }

    // MARK: request frame (len16BE || canonical JSON || padding)

    struct RelayRequest {
        let requestId: String       // 22-char b64url
        let challenge: Data         // 32 bytes
        let expiresAt: UInt32
        let viewBytes: Data
        let viewSha256: Data
    }

    static func decodeRequestFrame(_ frame: Data,
                                   requestId: String) -> RelayRequest? {
        guard frame.count == requestFrameBytes else { return nil }
        let len = Int(frame[frame.startIndex]) << 8 |
                  Int(frame[frame.startIndex + 1])
        guard len > 0, 2 + len <= frame.count else { return nil }
        let json = frame.subdata(
            in: frame.startIndex + 2 ..< frame.startIndex + 2 + len)
        guard let obj = (try? JSONSerialization.jsonObject(with: json))
                as? [String: Any],
              Set(obj.keys) == ["challenge", "expiresAt", "requestId",
                                "v", "view", "viewSha256"],
              obj["v"] as? Int == 1,
              let rid = obj["requestId"] as? String, rid == requestId,
              let challengeS = obj["challenge"] as? String,
              let challenge = b64urlDecode(challengeS),
              challenge.count == 32,
              let exp = obj["expiresAt"] as? UInt64, exp > 0,
              exp <= UInt64(UInt32.max),
              let viewS = obj["view"] as? String,
              let view = b64urlDecode(viewS),
              (1...maxViewBytes).contains(view.count),
              let shaS = obj["viewSha256"] as? String,
              let sha = b64urlDecode(shaS), sha.count == 32,
              Data(SHA256.hash(data: view)) == sha else { return nil }
        return RelayRequest(requestId: rid, challenge: challenge,
                            expiresAt: UInt32(exp), viewBytes: view,
                            viewSha256: sha)
    }

    // MARK: verdict frame

    static let verdictCodes: [String: UInt8] =
        ["approve": 1, "deny": 2, "terminal": 3, "panic": 4]

    static func verdictMacMessage(mailbox: String, requestIdRaw: Data,
                                  challenge: Data, viewSha256: Data,
                                  verdict: String) -> Data? {
        guard let code = verdictCodes[verdict] else { return nil }
        var m = Data("vibepulse-ir-verdict-v1".utf8)
        m.append(0)
        let box = Data(mailbox.utf8)
        m.append(UInt8(box.count >> 8))
        m.append(UInt8(box.count & 0xff))
        m.append(box)
        m.append(requestIdRaw)
        m.append(challenge)
        m.append(viewSha256)
        m.append(code)
        return m
    }

    /// Builds the sealed verdict envelope body. `padding` and `nonce` are
    /// injectable for the pinned test vectors; production passes random.
    static func sealedVerdict(keys: Keys, mailbox: String, requestId: String,
                              challenge: Data, viewSha256: Data,
                              verdict: String,
                              nonce: Data = randomBytes(nonceBytes),
                              padding: (Int) -> Data = randomBytes
                              ) -> Data? {
        guard let requestIdRaw = b64urlDecode(requestId),
              requestIdRaw.count == 16,
              let msg = verdictMacMessage(
                  mailbox: mailbox, requestIdRaw: requestIdRaw,
                  challenge: challenge, viewSha256: viewSha256,
                  verdict: verdict) else { return nil }
        let mac = Data(HMAC<SHA256>.authenticationCode(
            for: msg, using: keys.verdictMac))
        let json = "{\"challenge\":\"\(b64urlEncode(challenge))\"," +
            "\"hmac\":\"\(b64urlEncode(mac))\"," +
            "\"requestId\":\"\(requestId)\",\"v\":1," +
            "\"verdict\":\"\(verdict)\"," +
            "\"viewSha256\":\"\(b64urlEncode(viewSha256))\"}"
        let jsonData = Data(json.utf8)
        guard jsonData.count + 2 <= verdictFrameBytes else { return nil }
        var frame = Data()
        frame.append(UInt8(jsonData.count >> 8))
        frame.append(UInt8(jsonData.count & 0xff))
        frame.append(jsonData)
        frame.append(padding(verdictFrameBytes - frame.count))
        guard let sealed = seal(
            frame, key: keys.verdictAead,
            aad: verdictAAD(mailbox: mailbox, requestId: requestId),
            nonce: nonce) else { return nil }
        return envelopeJSON(ciphertext: sealed, nonce: nonce)
    }

    // MARK: status frame — "VPS1" binary header

    struct RelayStatus {
        let publicationId: UInt64
        let expiresAt: UInt32
        let statusBytes: Data
    }

    static func decodeStatusFrame(_ frame: Data) -> RelayStatus? {
        guard frame.count == statusFrameBytes else { return nil }
        let b = [UInt8](frame)
        guard b[0] == 0x56, b[1] == 0x50, b[2] == 0x53, b[3] == 0x31
        else { return nil }  // "VPS1"
        var pub: UInt64 = 0
        for i in 4..<12 { pub = pub << 8 | UInt64(b[i]) }
        var exp: UInt32 = 0
        for i in 12..<16 { exp = exp << 8 | UInt32(b[i]) }
        let len = Int(b[16]) << 8 | Int(b[17])
        guard pub > 0, exp > 0, len >= 1, len <= maxStatusBytes,
              statusHeaderBytes + len <= frame.count else { return nil }
        let digest = frame.subdata(
            in: frame.startIndex + 18 ..< frame.startIndex + 50)
        let status = frame.subdata(
            in: frame.startIndex + 50 ..< frame.startIndex + 50 + len)
        guard Data(SHA256.hash(data: status)) == digest else { return nil }
        return RelayStatus(publicationId: pub, expiresAt: exp,
                           statusBytes: status)
    }

    static func randomBytes(_ count: Int) -> Data {
        var d = Data(count: count)
        d.withUnsafeMutableBytes {
            _ = SecRandomCopyBytes(kSecRandomDefault, count,
                                   $0.baseAddress!)
        }
        return d
    }
}
