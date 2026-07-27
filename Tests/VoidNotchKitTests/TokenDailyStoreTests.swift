import Foundation
import XCTest
@testable import VoidNotchKit

final class TokenDailyStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenDailyStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func test_merge_usesIndependentMaximums_andNilDoesNotOverwrite() {
        let archive = [record("2025-01-01", "codex", costUsd: 2, tokens: 100)]
        let incoming = [
            record("2025-01-01", "codex", costUsd: nil, tokens: 150),
            record("2025-01-01", "codex", costUsd: 3, tokens: nil),
        ]

        let result = TokenDailyMerge.merge(
            archive: archive,
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-01")

        XCTAssertEqual(result, [record("2025-01-01", "codex", costUsd: 3, tokens: 150)])
    }

    func test_merge_acceptsDownwardRevisionOnNonOldestDate() {
        let archive = [record("2025-01-02", "codex", costUsd: 5.0, tokens: 50)]
        let incoming = [
            record("2025-01-01", "codex", costUsd: 1.0, tokens: 10),
            record("2025-01-02", "codex", costUsd: 3.0, tokens: 30),
        ]

        let result = TokenDailyMerge.merge(
            archive: archive,
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-02")

        XCTAssertEqual(
            result.first { $0.date == "2025-01-02" && $0.provider == "codex" },
            record("2025-01-02", "codex", costUsd: 3.0, tokens: 30))
    }

    func test_merge_blocksDownwardRevisionOnOldestDate() {
        let archive = [record("2025-01-01", "codex", costUsd: 5.0, tokens: 50)]
        let incoming = [record("2025-01-01", "codex", costUsd: 3.0, tokens: 30)]

        let result = TokenDailyMerge.merge(
            archive: archive,
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-01")

        XCTAssertEqual(result, [record("2025-01-01", "codex", costUsd: 5.0, tokens: 50)])
    }

    func test_mergeDoesNotLetNilOverwriteNonNilOnNonOldestDate() {
        let archive = [record("2025-01-02", "codex", costUsd: 5.0, tokens: 50)]
        let incoming = [
            record("2025-01-01", "codex", costUsd: 1.0, tokens: 10),
            record("2025-01-02", "codex", costUsd: nil, tokens: 30),
        ]

        let result = TokenDailyMerge.merge(
            archive: archive,
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-02")

        XCTAssertEqual(
            result.first { $0.date == "2025-01-02" && $0.provider == "codex" },
            record("2025-01-02", "codex", costUsd: 5.0, tokens: 30))
    }

    func test_mergeCalculatesOldestDateIndependentlyPerProvider() {
        let archive = [
            record("2025-01-02", "claude", costUsd: 5.0, tokens: 50),
            record("2025-01-02", "codex", costUsd: 5.0, tokens: 50),
        ]
        let incoming = [
            record("2025-01-01", "codex", costUsd: 1.0, tokens: 10),
            record("2025-01-02", "claude", costUsd: 3.0, tokens: 30),
            record("2025-01-02", "codex", costUsd: 3.0, tokens: 30),
        ]

        let result = TokenDailyMerge.merge(
            archive: archive,
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-02")

        XCTAssertEqual(
            result.first { $0.date == "2025-01-02" && $0.provider == "claude" },
            record("2025-01-02", "claude", costUsd: 5.0, tokens: 50))
        XCTAssertEqual(
            result.first { $0.date == "2025-01-02" && $0.provider == "codex" },
            record("2025-01-02", "codex", costUsd: 3.0, tokens: 30))
    }

    func test_merge_preservesArchiveOnlyRecords() {
        let archive = [record("2024-12-31", "claude", costUsd: 1, tokens: 10)]
        let incoming = [record("2025-01-01", "codex", costUsd: 2, tokens: 20)]

        let result = TokenDailyMerge.merge(
            archive: archive,
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-01")

        XCTAssertEqual(result, archive + incoming)
    }

    func test_merge_discardsIncomingDoubleNilRecords() {
        let archive = [record("2025-01-01", "codex", costUsd: 1, tokens: 10)]
        let incoming = [
            record("2025-01-01", "codex", costUsd: nil, tokens: nil),
            record("2025-01-01", "claude", costUsd: nil, tokens: nil),
        ]

        let result = TokenDailyMerge.merge(
            archive: archive,
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-01")

        XCTAssertEqual(result, archive)
    }

    func test_merge_discardsMalformedAndFutureDates() {
        let incoming = [
            record("2025-1-01", "bad", costUsd: 1, tokens: 1),
            record("20250101", "bad", costUsd: 1, tokens: 1),
            record("2025-01-02", "future", costUsd: 1, tokens: 1),
            record("2025-01-01", "valid", costUsd: 1, tokens: 1),
        ]

        let result = TokenDailyMerge.merge(
            archive: [],
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-01")

        XCTAssertEqual(result, [record("2025-01-01", "valid", costUsd: 1, tokens: 1)])
    }

    func test_merge_retains400thDayAndDrops401stDay() {
        let todayDate = makeDate(2025, 1, 1)
        let today = TokenDailyMerge.normalizedDateString(todayDate, calendar: calendar)
        let fourHundredthDate = calendar.date(byAdding: .day, value: -399, to: todayDate)!
        let fourHundredFirstDate = calendar.date(byAdding: .day, value: -400, to: todayDate)!
        let fourHundredth = TokenDailyMerge.normalizedDateString(fourHundredthDate, calendar: calendar)
        let fourHundredFirst = TokenDailyMerge.normalizedDateString(fourHundredFirstDate, calendar: calendar)

        let result = TokenDailyMerge.merge(
            archive: [],
            incoming: [
                record(fourHundredth, "codex", costUsd: 400, tokens: 400),
                record(fourHundredFirst, "codex", costUsd: 401, tokens: 401),
            ],
            retentionDays: 400,
            today: today)

        XCTAssertEqual(result.map(\.date), [fourHundredth])
    }

    func test_merge_sortsByDateThenProvider() {
        let incoming = [
            record("2025-01-02", "zeta", costUsd: 1, tokens: 1),
            record("2025-01-01", "zeta", costUsd: 1, tokens: 1),
            record("2025-01-02", "alpha", costUsd: 1, tokens: 1),
        ]

        let result = TokenDailyMerge.merge(
            archive: [],
            incoming: incoming,
            retentionDays: 400,
            today: "2025-01-02")

        XCTAssertEqual(
            result.map { "\($0.date)|\($0.provider)" },
            ["2025-01-01|zeta", "2025-01-02|alpha", "2025-01-02|zeta"])
    }

    func test_loadReturnsEmptyForBadJSONAndKeepsFile() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("nested/token-daily.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)

        let store = TokenDailyStore(fileURL: fileURL, calendar: calendar)

        XCTAssertEqual(store.load(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func test_ingestIsIdempotentAcrossTwoWrites() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("nested/token-daily.json")
        let store = TokenDailyStore(fileURL: fileURL, calendar: calendar)
        let now = makeDate(2025, 1, 1)
        let incoming = [record("2025-01-01", "codex", costUsd: 2, tokens: 100)]

        let first = try store.ingest(incoming, now: now)
        let second = try store.ingest(incoming, now: now)

        XCTAssertEqual(first, second)
        XCTAssertEqual(store.load(), incoming)
    }

    func test_seriesUsesInclusiveDateWindowAndOptionalProviderFilter() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("token-daily.json")
        let store = TokenDailyStore(fileURL: fileURL, calendar: calendar)
        let endingAt = makeDate(2025, 1, 4)
        let incoming = [
            record("2025-01-01", "codex", costUsd: 1, tokens: 1),
            record("2025-01-02", "codex", costUsd: 2, tokens: 2),
            record("2025-01-03", "codex", costUsd: 3, tokens: 3),
            record("2025-01-04", "codex", costUsd: 4, tokens: 4),
            record("2025-01-04", "claude", costUsd: 5, tokens: 5),
        ]
        _ = try store.ingest(incoming, now: endingAt)

        XCTAssertEqual(
            store.series(provider: "codex", days: 3, endingAt: endingAt),
            Array(incoming[1...3]))
        XCTAssertEqual(
            store.series(provider: nil, days: 1, endingAt: endingAt),
            [incoming[4], incoming[3]])
    }

    func test_ingest_preservesUnreadableBak_forBadJSON() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("bad-json/token-daily.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let badBytes = Data("not-json {{{".utf8)
        try badBytes.write(to: fileURL)

        let store = TokenDailyStore(fileURL: fileURL, calendar: calendar)
        let backupURL = store.preservedBackupURL()
        XCTAssertEqual(backupURL.lastPathComponent, "token-daily.json.unreadable.bak")

        _ = try store.ingest(
            [record("2025-01-01", "codex", costUsd: 1, tokens: 10)],
            now: makeDate(2025, 1, 1))

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let preserved = try Data(contentsOf: backupURL)
        XCTAssertEqual(preserved, badBytes)
    }

    func test_ingest_preservesUnreadableBak_forForeignVersion() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("version-2/token-daily.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let foreignArchive = TokenDailyArchive(
            version: 2,
            days: [record("2024-06-15", "legacy", costUsd: 9.5, tokens: 999)])
        let originalBytes = try JSONEncoder().encode(foreignArchive)
        try originalBytes.write(to: fileURL)

        let store = TokenDailyStore(fileURL: fileURL, calendar: calendar)
        let backupURL = store.preservedBackupURL()

        _ = try store.ingest(
            [record("2025-01-01", "codex", costUsd: 1, tokens: 10)],
            now: makeDate(2025, 1, 1))

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let preserved = try Data(contentsOf: backupURL)
        XCTAssertEqual(preserved, originalBytes)
    }

    func test_ingest_doesNotCreateBak_forReadableArchive() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("readable/token-daily.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let store = TokenDailyStore(fileURL: fileURL, calendar: calendar)
        let now = makeDate(2025, 1, 1)
        let seed = [record("2025-01-01", "codex", costUsd: 2, tokens: 100)]

        _ = try store.ingest(seed, now: now)
        let backupURL = store.preservedBackupURL()
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))

        _ = try store.ingest(seed, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    private func record(
        _ date: String,
        _ provider: String,
        costUsd: Double?,
        tokens: Int?) -> TokenDailyRecord
    {
        TokenDailyRecord(date: date, provider: provider, costUsd: costUsd, tokens: tokens)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
