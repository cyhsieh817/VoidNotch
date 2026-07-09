import XCTest
@testable import VoidNotchKit

final class AgentEventLogParserTests: XCTestCase {
    func test_parses_valid_jsonl_line() {
        let line = #"{"provider":"claude","status":"running","title":"Build","cwd":"/Users/x/Repo"}"#
        let event = AgentEventLogParser.parseEventLine(line)
        XCTAssertEqual(event?.provider, .claude)
        XCTAssertEqual(event?.status, .running)
        XCTAssertEqual(event?.title, "Build")
        XCTAssertEqual(event?.workspace, "Repo")
    }

    func test_malformed_or_empty_returns_nil() {
        XCTAssertNil(AgentEventLogParser.parseEventLine("{not json"))
        XCTAssertNil(AgentEventLogParser.parseEventLine(""))
    }

    func test_unknown_provider_or_status_returns_nil() {
        XCTAssertNil(AgentEventLogParser.parseEventLine(#"{"provider":"unknown","status":"running"}"#))
        XCTAssertNil(AgentEventLogParser.parseEventLine(#"{"provider":"claude","status":"floop"}"#))
    }

    func test_hook_event_name_maps_to_status() {
        let event = AgentEventLogParser.parseEventLine(#"{"agent":"codex","hook_event_name":"UserPromptSubmit"}"#)
        XCTAssertEqual(event?.provider, .codex)
        XCTAssertEqual(event?.status, .running)
    }

    func test_retention_filters_old_events() {
        let now = Date(timeIntervalSince1970: 10_000)
        let old = #"{"provider":"claude","status":"running","ts":1000}"#
        let fresh = #"{"provider":"claude","status":"running","ts":9999}"#
        let events = AgentEventLogParser.parse(text: "\(old)\n\(fresh)",
                                               retentionCutoff: now.addingTimeInterval(-3600))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.occurredAt, Date(timeIntervalSince1970: 9999))
    }
}
