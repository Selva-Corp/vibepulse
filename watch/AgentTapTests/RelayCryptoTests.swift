// Pinned against the repo's cross-language reference vectors — the same
// files the Python and C implementations verify against.
import CryptoKit
import XCTest
@testable import AgentTap

final class RelayCryptoTests: XCTestCase {
    func vector(_ name: String) -> [String: Any] {
        let url = Bundle(for: Self.self).url(forResource: name,
                                             withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func hex(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }

    func keyHex(_ k: SymmetricKey) -> String {
        k.withUnsafeBytes { hex(Data($0)) }
    }

    func testInteractionVector() throws {
        let v = vector("interaction-relay-v1")
        let inp = v["inputs"] as! [String: Any]
        let exp = v["expected"] as! [String: Any]
        let deviceKey = RelayCrypto.decodeDeviceKey(
            hex: inp["deviceKeyHex"] as! String)!
        let mailbox = inp["mailbox"] as! String
        let keys = RelayCrypto.deriveKeys(deviceKey: deviceKey,
                                          mailbox: mailbox)
        XCTAssertEqual(keyHex(keys.requestAead),
                       exp["requestKeyHex"] as! String)
        XCTAssertEqual(keyHex(keys.verdictAead),
                       exp["verdictKeyHex"] as! String)
        XCTAssertEqual(keyHex(keys.verdictMac),
                       exp["verdictMacKeyHex"] as! String)

        let requestId = inp["requestId"] as! String
        XCTAssertEqual(RelayCrypto.requestAAD(mailbox: mailbox,
                                              requestId: requestId),
                       exp["requestAadUtf8"] as! String)
        XCTAssertEqual(RelayCrypto.verdictAAD(mailbox: mailbox,
                                              requestId: requestId),
                       exp["verdictAadUtf8"] as! String)

        // Decrypt the pinned request envelope end-to-end.
        let envObj = try JSONSerialization.jsonObject(
            with: Data((exp["requestEnvelopeUtf8"] as! String).utf8))
            as! [String: Any]
        let envelope = RelayCrypto.parseEnvelope(
            envObj, expectCiphertext: 2064)!
        let frame = RelayCrypto.open(
            envelope, key: keys.requestAead,
            aad: RelayCrypto.requestAAD(mailbox: mailbox,
                                        requestId: requestId))!
        let request = RelayCrypto.decodeRequestFrame(frame,
                                                     requestId: requestId)!
        XCTAssertEqual(hex(request.challenge),
                       inp["challengeHex"] as! String)
        XCTAssertEqual(request.expiresAt,
                       UInt32(inp["expiresAt"] as! Int))
        XCTAssertEqual(RelayCrypto.b64urlEncode(request.viewSha256),
                       exp["viewSha256Base64url"] as! String)

        // Rebuild the pinned verdict envelope byte-for-byte.
        let challenge = RelayCrypto.b64urlDecode(
            RelayCrypto.b64urlEncode(request.challenge))!
        let padByte = UInt8((inp["paddingByteHex"] as! String), radix: 16)!
        let nonce = RelayCrypto.decodeDeviceKey(
            hex: String(repeating: "00", count: 20)
                + (inp["verdictNonceHex"] as! String))!.suffix(12)
        let body = RelayCrypto.sealedVerdict(
            keys: keys, mailbox: mailbox, requestId: requestId,
            challenge: challenge, viewSha256: request.viewSha256,
            verdict: "approve",
            nonce: Data(nonce),
            padding: { Data(repeating: padByte, count: $0) })!
        XCTAssertEqual(String(data: body, encoding: .utf8),
                       exp["verdictEnvelopeUtf8"] as! String)

        // And the MAC message itself.
        let msg = RelayCrypto.verdictMacMessage(
            mailbox: mailbox,
            requestIdRaw: RelayCrypto.b64urlDecode(requestId)!,
            challenge: challenge, viewSha256: request.viewSha256,
            verdict: "approve")!
        XCTAssertEqual(hex(msg), exp["verdictMacMessageHex"] as! String)
    }

    func testStatusVector() throws {
        let v = vector("agent-status-relay-v1")
        let inp = v["inputs"] as! [String: Any]
        let exp = v["expected"] as! [String: Any]
        let keys = RelayCrypto.deriveKeys(
            deviceKey: RelayCrypto.decodeDeviceKey(
                hex: inp["deviceKeyHex"] as! String)!,
            mailbox: inp["mailbox"] as! String)
        XCTAssertEqual(keyHex(keys.statusAead),
                       exp["statusKeyHex"] as! String)
        XCTAssertEqual(RelayCrypto.statusAAD(
            mailbox: inp["mailbox"] as! String),
                       exp["statusAadUtf8"] as! String)
        let envObj = try JSONSerialization.jsonObject(
            with: Data((exp["statusEnvelopeUtf8"] as! String).utf8))
            as! [String: Any]
        let envelope = RelayCrypto.parseEnvelope(
            envObj, expectCiphertext: 2832)!
        let frame = RelayCrypto.open(
            envelope, key: keys.statusAead,
            aad: RelayCrypto.statusAAD(mailbox: inp["mailbox"] as! String))!
        let status = RelayCrypto.decodeStatusFrame(frame)!
        XCTAssertEqual(status.publicationId,
                       UInt64(inp["publicationId"] as! Int))
        XCTAssertEqual(status.expiresAt, UInt32(inp["expiresAt"] as! Int))
        XCTAssertEqual(hex(Data(SHA256.hash(data: status.statusBytes))),
                       exp["statusSha256Hex"] as! String)
    }

    func testNegativeVectors() {
        // Padded base64, wrong nonce length, truncated tag — all refused.
        XCTAssertNil(RelayCrypto.b64urlDecode("QUJD="))
        XCTAssertNil(RelayCrypto.parseEnvelope(
            ["ciphertext": "AAAA", "nonce": "AAAA", "v": 1],
            expectCiphertext: 3))
        XCTAssertNil(RelayCrypto.decodeStatusFrame(
            Data(repeating: 0, count: 2816)))
    }
}

extension RelayCryptoTests {
    /// Regression: the LAN pending carries its digest as 64 HEX chars.
    /// Feeding hex to the base64url decoder yields 48 garbage bytes and a
    /// verdict the Mac silently refuses — this pins the correct path.
    func testHexDigestConvertsTo32BytesNeverBase64() {
        let hex = String(repeating: "ab", count: 32)
        let viaHex = RelayCrypto.decodeDeviceKey(hex: hex)
        XCTAssertEqual(viaHex?.count, 32)
        let viaB64 = RelayCrypto.b64urlDecode(hex)
        XCTAssertEqual(viaB64?.count, 48)  // the trap: valid b64, wrong data
        XCTAssertNotEqual(viaHex, viaB64)
    }
}
