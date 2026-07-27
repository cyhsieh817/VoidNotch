import Foundation
import XCTest
@testable import VoidNotchKit

final class ContributionCalendarGridTests: XCTestCase {
    // MARK: - ContributionCalendarGrid

    func test_emptyInput_returnsEmptyArray() {
        let grid = ContributionCalendarGrid.build(days: [], endDate: "")
        XCTAssertEqual(grid, [])
    }

    func test_eachColumnHasExactlySevenCells_andOutOfWindowIsNegativeOne() {
        // endDate 2026-07-13 is Monday (UTC weekday 2). cutoff 2025-07-14 is also Monday.
        // leadingDays = weekday-1 = 1 (Sunday pad); trailingDays = 5 (Tue–Sat after end).
        let grid = ContributionCalendarGrid.build(
            days: [(date: "2026-07-03", costUsd: 10)],
            endDate: "2026-07-13")

        XCTAssertFalse(grid.isEmpty)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })

        let cells = grid.flatMap { $0 }
        XCTAssertTrue(cells.contains(-1), "padded out-of-window cells must be -1")
        XCTAssertEqual(cells[0], -1, "leading Sunday pad before Monday cutoff")
        // Trailing pad after endDate (Mon) through Saturday → 5 cells of -1
        XCTAssertEqual(Array(cells.suffix(5)), [-1, -1, -1, -1, -1])
    }

    /// With fewer than 4 positive days, percentile thresholds collapse onto early ranks.
    /// Pin the *actual* buckets — do not assume values spread across 1…4.
    func test_fewerThanFourPositiveDays_percentileBucketsCollapse() {
        // Three distinct positive costs → sortedCosts.count == 3.
        // threshold(p) = sortedCosts[Int((3-1)*p)] → p0.25→idx0, p0.50→idx1, p0.75→idx1
        // so 1→bucket 1, 10→bucket 2, 100→bucket 4 (no bucket 3 is reachable).
        let grid = ContributionCalendarGrid.build(
            days: [
                (date: "2026-07-10", costUsd: 1),
                (date: "2026-07-11", costUsd: 10),
                (date: "2026-07-12", costUsd: 100),
            ],
            endDate: "2026-07-13")
        let cells = grid.flatMap { $0 }
        let positiveBuckets = cells.filter { $0 > 0 }.sorted()

        XCTAssertEqual(
            positiveBuckets,
            [1, 2, 4],
            "small-sample percentiles must collapse (here: 1,2,4 — never assume full 1…4 spread)")

        // Single positive day: all thresholds land on the only value → always bucket 1.
        let single = ContributionCalendarGrid.build(
            days: [(date: "2026-07-10", costUsd: 42)],
            endDate: "2026-07-13")
        let singlePositive = single.flatMap { $0 }.filter { $0 > 0 }
        XCTAssertEqual(singlePositive, [1])
    }

    func test_datesOutside364DayWindow_areExcluded() {
        // endDate 2026-07-13 → cutoff 2025-07-14 (inclusive window of 365 calendar days).
        // 2025-07-13 is one day before cutoff and must not appear as a positive bucket.
        let grid = ContributionCalendarGrid.build(
            days: [
                (date: "2025-07-13", costUsd: 999), // outside window
                (date: "2025-07-14", costUsd: 1), // first in-window day
                (date: "2026-07-13", costUsd: 100), // end day
                (date: "2026-07-14", costUsd: 999), // after end
            ],
            endDate: "2026-07-13")
        let cells = grid.flatMap { $0 }

        XCTAssertEqual(grid.count, 53)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        XCTAssertEqual(cells.count, 371)

        // With only two positive in-window costs [1, 100], thresholds collapse to min:
        // both thresholds at index 0 → cost 1 → 1, cost 100 → 4.
        // leading pad occupies cells[0]; first in-window day (cutoff) is cells[1].
        XCTAssertEqual(cells[0], -1, "leading Sunday pad")
        XCTAssertEqual(cells[1], 1, "cutoff day should be bucketed; pre-cutoff 999 excluded")
        XCTAssertEqual(cells[365], 4, "end day should be bucketed; post-end 999 excluded")
        // Out-of-window 999s must not create extra positive cells beyond the two above.
        let positive = cells.filter { $0 > 0 }
        XCTAssertEqual(positive.sorted(), [1, 4])
        XCTAssertEqual(Array(cells[366...370]), [-1, -1, -1, -1, -1])
    }

    // MARK: - adaptiveWindowDays

    func test_adaptiveWindowDays_only30Days_returnsMinimum() {
        // end 2026-07-13, earliest 30 days earlier → span 30 < minimum 90
        let window = ContributionCalendarGrid.adaptiveWindowDays(
            earliestDate: "2026-06-13",
            endDate: "2026-07-13")
        XCTAssertEqual(window, 90)
        XCTAssertEqual(window % 7, 6)
    }

    func test_adaptiveWindowDays_200Days_roundsUpToFullWeek() {
        // end 2026-07-13, earliest 200 days earlier
        let window = ContributionCalendarGrid.adaptiveWindowDays(
            earliestDate: "2025-12-25",
            endDate: "2026-07-13")
        // 200 % 7 == 4 → ceil to 202 (202 % 7 == 6)
        XCTAssertEqual(window, 202)
        XCTAssertEqual(window % 7, 6)
        XCTAssertGreaterThanOrEqual(window, 200)
        XCTAssertLessThanOrEqual(window, 210)
    }

    func test_adaptiveWindowDays_over364Days_clampsToMaximum() {
        // span far beyond a year → clamp to maximum 364
        let window = ContributionCalendarGrid.adaptiveWindowDays(
            earliestDate: "2024-01-01",
            endDate: "2026-07-13")
        XCTAssertEqual(window, 364)
    }

    func test_adaptiveWindowDays_nilEarliest_returnsMinimum() {
        let window = ContributionCalendarGrid.adaptiveWindowDays(
            earliestDate: nil,
            endDate: "2026-07-13")
        XCTAssertEqual(window, 90)
    }

    func test_adaptiveWindowDays_unparseableEarliest_returnsMinimum() {
        let window = ContributionCalendarGrid.adaptiveWindowDays(
            earliestDate: "not-a-date",
            endDate: "2026-07-13")
        XCTAssertEqual(window, 90)
    }

    // MARK: - build windowDays

    func test_build_windowDaysZeroOrNegative_returnsEmpty() {
        XCTAssertEqual(
            ContributionCalendarGrid.build(
                days: [(date: "2026-07-10", costUsd: 1)],
                endDate: "2026-07-13",
                windowDays: 0),
            [])
        XCTAssertEqual(
            ContributionCalendarGrid.build(
                days: [(date: "2026-07-10", costUsd: 1)],
                endDate: "2026-07-13",
                windowDays: -7),
            [])
    }

    func test_build_smallerWindowDays_yieldsFewerColumns() {
        let days: [(date: String, costUsd: Double)] = [
            (date: "2026-07-10", costUsd: 1),
            (date: "2026-07-11", costUsd: 2),
            (date: "2026-07-12", costUsd: 3),
        ]
        let full = ContributionCalendarGrid.build(
            days: days,
            endDate: "2026-07-13")
        let short = ContributionCalendarGrid.build(
            days: days,
            endDate: "2026-07-13",
            windowDays: 27) // 27 % 7 == 6 → ~4 weeks of in-window days
        XCTAssertTrue(full.allSatisfy { $0.count == 7 })
        XCTAssertTrue(short.allSatisfy { $0.count == 7 })
        XCTAssertLessThan(short.count, full.count)
        // Default window is ~53 columns; a 28-day-ish window should be well under 20.
        XCTAssertLessThan(short.count, 20)
        XCTAssertGreaterThan(full.count, 50)
    }

    // MARK: - TokenStore dailySeries accessor

    @MainActor
    func test_tokenStore_dailySeries_returnsEmptyWhenDailyStoreNil() {
        let store = TokenStore(
            usageProvider: UnavailableTokenUsageProvider(),
            defaults: makeTestDefaults("ContributionCalendarGrid"))
        XCTAssertEqual(store.dailySeries(days: 7, endingAt: Date()), [])
    }

    @MainActor
    func test_tokenStore_dailySeries_delegatesToDailyStore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContributionCalendarGridTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dailyStore = TokenDailyStore(
            fileURL: dir.appendingPathComponent("token-daily.json"),
            calendar: calendar)
        let endingAt = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))!

        try dailyStore.ingest(
            [
                TokenDailyRecord(date: "2026-07-11", provider: "codex", costUsd: 1, tokens: 10),
                TokenDailyRecord(date: "2026-07-12", provider: "claude", costUsd: 2, tokens: 20),
                TokenDailyRecord(date: "2026-07-13", provider: "codex", costUsd: 3, tokens: 30),
            ],
            now: endingAt)

        let store = TokenStore(
            usageProvider: UnavailableTokenUsageProvider(),
            defaults: makeTestDefaults("ContributionCalendarGrid"),
            dailyStore: dailyStore)

        let series = store.dailySeries(days: 2, endingAt: endingAt)
        XCTAssertEqual(series.map(\.date), ["2026-07-12", "2026-07-13"])
        XCTAssertEqual(Set(series.map(\.provider)), Set(["claude", "codex"]))
    }
}
