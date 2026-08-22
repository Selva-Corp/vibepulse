// Crypto pinned against the tokenserver reference implementation
// (tools/tokenserver/interactions.py sign_answer_v2 / panic). Vectors were
// generated with Python hmac/hashlib this session; key is synthetic.
import XCTest

final class SignerTests: XCTestCase {
    let signer = Signer(deviceKeyHex: String(repeating: "a", count: 64))

    func testV2AnswerVector() {
        let msg = "v2|claude|vqgs5_NFsCc2-cBwEEHn8w|"
            + "3f6e059723ba3da94e21402909b642ce8741133eea5996a5eb30b344f301841f"
            + "|approve|1755870000"
        XCTAssertEqual(
            signer.hmacHex(msg),
            "59f8209e22ed2d5a97ce27187f5589a616f44a650120ba7f1b92ed2bdf8f0317")
    }

    func testPanicVector() {
        XCTAssertEqual(
            signer.hmacHex("panic|deny|1755870000"),
            "4a898dcfda38b7fbb550f406f0023b1a5cab580fecfe09595dfcd2fa9d311de4")
    }

    func testAnswerBodyIsIntegerTimestampJSON() throws {
        let body = signer.answerBody(
            provider: "claude", requestID: "vqgs5_NFsCc2-cBwEEHn8w",
            viewSHA256: "3f6e059723ba3da94e21402909b642ce8741133eea5996a5eb30b344f301841f",
            verdict: .approve, ts: 1755870000)
        let text = String(data: body, encoding: .utf8)!
        XCTAssertTrue(text.contains("\"ts\":1755870000,"))
        XCTAssertFalse(text.contains("1755870000.0"))
        let obj = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(obj["verdict"] as? String, "approve")
        XCTAssertEqual(
            obj["hmac"] as? String,
            "59f8209e22ed2d5a97ce27187f5589a616f44a650120ba7f1b92ed2bdf8f0317")
    }

    func testKeyTrimming() {
        let padded = Signer(deviceKeyHex: String(repeating: "a", count: 64) + "\n")
        XCTAssertTrue(padded.hasKey)
        XCTAssertEqual(padded.hmacHex("panic|deny|1755870000"),
                       signer.hmacHex("panic|deny|1755870000"))
    }
}
