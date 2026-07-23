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

    /// 截斷點落在中文字（3 bytes）中間時，仍應解碼成功並讀出尾段完整事件。
    func test_tail_read_recovers_when_cut_splits_multibyte_utf8() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        let completeEvent = #"{"provider":"codex","status":"completed","title":"完成","ts":4102444800}"#
        // 前綴：偶數個 ASCII 後接「中」（3 bytes），使 suffix(maxBytes) 的起點落在「中」的第 2 個 byte。
        // 檔案 = prefix + "\n" + event + "\n"；maxBytes 取 event 尾段，且 cut 點對齊「中」中間。
        let chinese = "中"
        let chineseUTF8 = Array(chinese.utf8)
        XCTAssertEqual(chineseUTF8.count, 3)

        let eventLine = completeEvent + "\n"
        let eventBytes = Array(eventLine.utf8)
        // 在 cut 點前放 1 byte 的「中」前導（不完整），再接完整「中」的剩餘 2 bytes… 更直接：
        // 構造整檔 data，令 start = count - maxBytes 恰為「中」的第 2 byte 索引。
        let leadASCII = Data(repeating: UInt8(ascii: "x"), count: 50)
        let chineseData = Data(chinese.utf8) // 3 bytes
        let newline = Data([UInt8(ascii: "\n")])
        let eventData = Data(eventLine.utf8)
        // [50 x][中 3bytes][\n][event\n]
        var fileData = Data()
        fileData.append(leadASCII)
        fileData.append(chineseData)
        fileData.append(newline)
        fileData.append(eventData)

        // 起點落在「中」的第 2 個 byte（index = 50 + 1）
        let cutStart = leadASCII.count + 1 // 中間 byte
        let maxBytes = fileData.count - cutStart
        XCTAssertGreaterThan(maxBytes, eventBytes.count)
        // 確認裸 suffix 確實無法 UTF-8 解碼（本測試核心前置條件）
        let rawTail = fileData.suffix(maxBytes)
        XCTAssertNil(String(data: Data(rawTail), encoding: .utf8),
                     "前置條件：截斷點必須落在多位元組字元中間")

        try fileData.write(to: url)

        let events = AgentEventLogReader.loadEvents(
            from: url,
            maxReadBytes: maxBytes,
            retentionSeconds: 24 * 60 * 60)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.provider, .codex)
        XCTAssertEqual(events.first?.status, .completed)
        XCTAssertEqual(events.first?.title, "完成")
    }

    /// 純 ASCII 且超過 maxBytes 時仍應正常讀取尾段事件。
    func test_tail_read_ascii_over_max_bytes_still_works() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        let completeEvent = #"{"provider":"claude","status":"completed","title":"Done","ts":4102444800}"#
        let padding = String(repeating: "a", count: 512) + "\n"
        let text = padding + completeEvent + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        let maxBytes = completeEvent.utf8.count + 32
        XCTAssertGreaterThan(text.utf8.count, maxBytes)

        let events = AgentEventLogReader.loadEvents(
            from: url,
            maxReadBytes: maxBytes,
            retentionSeconds: 24 * 60 * 60)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.provider, .claude)
        XCTAssertEqual(events.first?.status, .completed)
        XCTAssertEqual(events.first?.title, "Done")
    }

    /// 檔案不存在時回傳空陣列。
    func test_missing_file_returns_empty_array() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-missing-\(UUID().uuidString)")
            .appendingPathComponent("no-such-agent-events.jsonl")

        let events = AgentEventLogReader.loadEvents(
            from: url,
            retentionSeconds: 24 * 60 * 60)

        XCTAssertTrue(events.isEmpty)
    }

    func test_change_detector_skips_second_read_for_unchanged_file() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        let event = #"{"provider":"codex","status":"completed","title":"First","ts":4102444800}"#
        try (event + "\n").write(to: url, atomically: true, encoding: .utf8)
        let detector = AgentEventLogChangeDetector(eventLogURL: url)
        var readCount = 0

        let shouldReadFirst = await detector.prepareToFetch()
        if shouldReadFirst {
            _ = AgentEventLogReader.loadEvents(from: url, retentionSeconds: 24 * 60 * 60)
            readCount += 1
            await detector.commitFetched()
        }

        let shouldReadSecond = await detector.prepareToFetch()
        if shouldReadSecond {
            _ = AgentEventLogReader.loadEvents(from: url, retentionSeconds: 24 * 60 * 60)
            readCount += 1
            await detector.commitFetched()
        }

        XCTAssertTrue(shouldReadFirst)
        XCTAssertFalse(shouldReadSecond)
        XCTAssertEqual(readCount, 1)
    }

    func test_change_detector_reads_again_after_file_size_changes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        let first = #"{"provider":"codex","status":"completed","title":"First","ts":4102444800}"#
        let second = #"{"provider":"claude","status":"completed","title":"Second","ts":4102444801}"#
        try (first + "\n").write(to: url, atomically: true, encoding: .utf8)
        let detector = AgentEventLogChangeDetector(eventLogURL: url)

        let shouldReadFirst = await detector.prepareToFetch()
        XCTAssertTrue(shouldReadFirst)
        var events = AgentEventLogReader.loadEvents(from: url, retentionSeconds: 24 * 60 * 60)
        await detector.commitFetched()
        XCTAssertEqual(events.map(\.title), ["First"])

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((second + "\n").utf8))
        try handle.close()

        let shouldReadSecond = await detector.prepareToFetch()
        XCTAssertTrue(shouldReadSecond)
        events = AgentEventLogReader.loadEvents(from: url, retentionSeconds: 24 * 60 * 60)
        await detector.commitFetched()
        XCTAssertEqual(Set(events.map(\.title)), Set(["First", "Second"]))
    }

    func test_file_handle_tail_read_recovers_from_chinese_utf8_midpoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        let event = #"{"provider":"codex","status":"completed","title":"尾端完成","ts":4102444800}"# + "\n"
        let prefix = Data(repeating: UInt8(ascii: "p"), count: 80)
        var fileData = prefix
        fileData.append(Data("中".utf8))
        fileData.append(Data([UInt8(ascii: "\n")]))
        fileData.append(Data(event.utf8))
        try fileData.write(to: url)

        let cutStart = prefix.count + 1
        let maxReadBytes = fileData.count - cutStart
        XCTAssertNil(String(data: Data(fileData.suffix(maxReadBytes)), encoding: .utf8))

        let events = AgentEventLogReader.loadEvents(
            from: url,
            maxReadBytes: maxReadBytes,
            retentionSeconds: 24 * 60 * 60)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "尾端完成")
    }
}
