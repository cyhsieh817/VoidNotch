import XCTest
@testable import VoidNotchKit

final class AgentEventLogReaderTests: XCTestCase {
    func test_creates_parent_directory_when_requested_and_missing_file_returns_empty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("agent-events.jsonl")

        let events = AgentEventLogReader.loadEvents(
            from: url,
            retentionSeconds: 24 * 60 * 60,
            createDirectoryIfMissing: true)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(events.isEmpty)
    }

    func test_tail_read_drops_partial_first_line_and_keeps_complete_events() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        let completeEvent = #"{"provider":"codex","status":"completed","title":"Done","ts":4102444800}"#
        let text = String(repeating: "x", count: 128) + "\n" + completeEvent + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        let events = AgentEventLogReader.loadEvents(
            from: url,
            maxReadBytes: completeEvent.utf8.count + 4,
            retentionSeconds: 24 * 60 * 60)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.provider, .codex)
        XCTAssertEqual(events.first?.status, .completed)
        XCTAssertEqual(events.first?.title, "Done")
    }

    func test_tail_read_returns_empty_when_window_has_no_line_boundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        let text = #"{"provider":"claude","status":"running","title":"Long","# + String(repeating: "x", count: 256)
        try text.write(to: url, atomically: true, encoding: .utf8)

        let events = AgentEventLogReader.loadEvents(
            from: url,
            maxReadBytes: 16,
            retentionSeconds: 24 * 60 * 60)

        XCTAssertTrue(events.isEmpty)
    }
}
