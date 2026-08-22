// The canonical view must byte-match Python json.dumps(sort_keys=True,
// separators=(",",":"), ensure_ascii=False). Fixtures captured live from the
// running tokenserver this session.
import XCTest

final class CanonicalViewTests: XCTestCase {
    /// Live capture: parked question with detail on.
    let livePendingJSON = """
    {"request_id":"vqgs5_NFsCc2-cBwEEHn8w","project":"vibepulse",
     "expires_in_ms":119003,"hold_ms":120000,"provider":"claude",
     "kind":"question","options_total":2,"marked":true,
     "prompt":"Protocol proof: approve the reference signer?",
     "title":"Yes, signer works","subtitle":"Reference vectors verified",
     "can_approve":true,
     "view_sha256":"3f6e059723ba3da94e21402909b642ce8741133eea5996a5eb30b344f301841f"}
    """

    func testLiveQuestionCanonicalAndDigest() throws {
        let any = try JSONSerialization.jsonObject(
            with: Data(livePendingJSON.utf8))
        let p = try XCTUnwrap(Pending.parse(any))
        XCTAssertEqual(p.canonicalView,
            "{\"can_approve\":true,\"hold_ms\":120000,\"kind\":\"question\","
            + "\"marked\":true,\"options_total\":2,\"project\":\"vibepulse\","
            + "\"prompt\":\"Protocol proof: approve the reference signer?\","
            + "\"provider\":\"claude\",\"request_id\":\"vqgs5_NFsCc2-cBwEEHn8w\","
            + "\"subtitle\":\"Reference vectors verified\","
            + "\"title\":\"Yes, signer works\"}")
        XCTAssertTrue(p.digestValid)
    }

    func testNonASCIIAndQuoteEscaping() {
        // Python: {"can_approve":false,...,"project":"täst \"q\"",...}
        // digest f846fcaf372be23af441e8774051d52e1ccfb274270d38d0ff6ec3fa541d94ee
        let p = Pending(
            requestID: "AAAAAAAAAAAAAAAAAAAAAA", provider: "claude",
            kind: "approval", project: "täst \"q\"", expiresInMS: 1000,
            holdMS: 120000, optionsTotal: nil, marked: nil, tool: "Bash",
            prompt: nil, title: nil, subtitle: nil, canApprove: false,
            viewSHA256: "f846fcaf372be23af441e8774051d52e1ccfb274270d38d0ff6ec3fa541d94ee",
            fetchedAt: .now)
        XCTAssertTrue(p.digestValid)
    }

    func testDigestMismatchIsRefused() throws {
        var tampered = try XCTUnwrap(Pending.parse(
            JSONSerialization.jsonObject(with: Data(livePendingJSON.utf8))))
        tampered.prompt = "Protocol proof: approve the reference signer!"
        XCTAssertFalse(tampered.digestValid)
    }

    func testControlCharacterEscaping() {
        XCTAssertEqual(Pending.jsonEscape("a\nb\t\"c\"\\d\u{1f}"),
                       "a\\nb\\t\\\"c\\\"\\\\d\\u001f")
    }
}
