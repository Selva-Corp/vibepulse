import XCTest

final class ParseTests: XCTestCase {
    func testTokensPairRuleAndUnknownKeys() throws {
        let json = """
        {"v":2,"unknownFutureKey":{"x":1},
         "claudeSessionPct":0.0,"claudeSessionResetMin":291,
         "claudeWeekPct":2.0,"claudeWeekResetMin":7591,"claudeWeekStale":false,
         "claudeModelWeekPct":2.0,"claudeModelWeekResetMin":7591,
         "claudeModelWeekLabel":"FABLE · WEEK","claudeModelWeekStale":true,
         "codexSessionPct":null,"codexSessionResetMin":null,
         "codexWeekPct":55.5,"codexWeekResetMin":null}
        """
        let snap = try XCTUnwrap(TokensSnapshot.parse(Data(json.utf8)))
        XCTAssertEqual(snap.claudeSession?.resetMin, 291)
        XCTAssertEqual(snap.claudeModelWeek?.stale, true)
        XCTAssertEqual(snap.claudeModelWeekLabel, "FABLE · WEEK")
        XCTAssertNil(snap.codexSession)          // both null
        XCTAssertNil(snap.codexWeek)             // pct without reset = invalid
    }

    func testTokensRejectsWrongVersionAndErrorBody() {
        XCTAssertNil(TokensSnapshot.parse(Data("{\"v\":1}".utf8)))
        XCTAssertNil(TokensSnapshot.parse(
            Data("{\"v\":2,\"error\":\"nope\"}".utf8)))
    }

    func testAgentStatusSurvivesMalformedPending() throws {
        let json = """
        {"v":2,"seq":519,"agents":{
          "claude":{"active_count":1,"jobs":[
            {"task_id":"t1","event_id":"e1","state":"working",
             "project":"vibepulse","activity":"running","model":"OPUS 5",
             "updated_ms":1891}]},
          "codex":{"active_count":0,"jobs":[]}},
         "pending":"garbage-not-an-object"}
        """
        let status = try XCTUnwrap(AgentStatus.parse(Data(json.utf8)))
        XCTAssertEqual(status.claude.count, 1)
        XCTAssertEqual(status.claude[0].project, "vibepulse")
        XCTAssertNil(status.pending)
    }

    func testPendingStrictness() {
        // hold_ms as boolean must not pass the integer reader.
        let bad: [String: Any] = [
            "request_id": "x", "provider": "claude", "kind": "approval",
            "expires_in_ms": 1000, "hold_ms": true, "can_approve": false,
            "view_sha256": String(repeating: "0", count: 64)]
        XCTAssertNil(Pending.parse(bad))
        // Unknown provider is refused.
        var unknown = bad
        unknown["hold_ms"] = 120000
        unknown["provider"] = "gemini"
        XCTAssertNil(Pending.parse(unknown))
    }

    func testJobRanking() throws {
        let json = """
        {"v":2,"seq":1,"agents":{
          "claude":{"active_count":3,"jobs":[
            {"task_id":"a","event_id":"1","state":"done","project":"p1","updated_ms":5},
            {"task_id":"b","event_id":"2","state":"waiting","project":"p2","updated_ms":9},
            {"task_id":"c","event_id":"3","state":"working","project":"p3","updated_ms":1}]},
          "codex":{"active_count":0,"jobs":[]}}}
        """
        let status = try XCTUnwrap(AgentStatus.parse(Data(json.utf8)))
        XCTAssertEqual(status.claude.map(\.project), ["p2", "p3", "p1"])
    }
}
