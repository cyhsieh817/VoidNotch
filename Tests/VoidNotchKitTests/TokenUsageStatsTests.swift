import Foundation
import XCTest
@testable import VoidNotchKit

final class TokenUsageStatsTests: XCTestCase {
    // MARK: - summary

    func test_summary_emptyInput_returnsZerosAndNils() {
        let summary = TokenUsageStats.summary(records: [])

        XCTAssertEqual(summary.totalCost, 0)
        XCTAssertEqual(summary.totalTokens, 0)
        XCTAssertEqual(summary.activeDays, 0)
        XCTAssertEqual(summary.dailyAverageCost, 0)
        XCTAssertNil(summary.peakDay)
        XCTAssertNil(summary.earliestDate)
        XCTAssertNil(summary.latestDate)
    }

    func test_summary_singleProvider_totalsActiveDaysAverageAndPeak() {
        let records = [
            record("2026-07-10", "codex", costUsd: 1.0, tokens: 100),
            record("2026-07-11", "codex", costUsd: 3.0, tokens: 300),
            record("2026-07-12", "codex", costUsd: 0, tokens: 10),
        ]

        let summary = TokenUsageStats.summary(records: records)

        XCTAssertEqual(summary.totalCost, 4.0)
        XCTAssertEqual(summary.totalTokens, 410)
        XCTAssertEqual(summary.activeDays, 2, "only days with positive cost count")
        XCTAssertEqual(summary.dailyAverageCost, 2.0)
        XCTAssertEqual(summary.peakDay, TokenUsageStats.PeakDay(date: "2026-07-11", cost: 3.0))
        XCTAssertEqual(summary.earliestDate, "2026-07-10")
        XCTAssertEqual(summary.latestDate, "2026-07-12")
    }

    func test_summary_peakDay_aggregatesAcrossProviders_andPicksHighestCostDay() {
        let records = [
            record("2026-07-10", "codex", costUsd: 2.0, tokens: 20),
            record("2026-07-10", "claude", costUsd: 1.0, tokens: 10),
            record("2026-07-11", "codex", costUsd: 5.0, tokens: 50),
            record("2026-07-11", "claude", costUsd: 0.5, tokens: 5),
            record("2026-07-12", "codex", costUsd: 4.0, tokens: 40),
        ]

        let summary = TokenUsageStats.summary(records: records)

        // 07-10: 3.0, 07-11: 5.5, 07-12: 4.0
        XCTAssertEqual(summary.peakDay, TokenUsageStats.PeakDay(date: "2026-07-11", cost: 5.5))
        XCTAssertEqual(summary.totalCost, 12.5)
        XCTAssertEqual(summary.activeDays, 3)
    }

    func test_summary_nilFields_treatedAsZero_doNotCrash() {
        let records = [
            record("2026-07-10", "codex", costUsd: nil, tokens: nil),
            record("2026-07-11", "codex", costUsd: 2.0, tokens: nil),
            record("2026-07-12", "claude", costUsd: nil, tokens: 50),
        ]

        let summary = TokenUsageStats.summary(records: records)

        XCTAssertEqual(summary.totalCost, 2.0)
        XCTAssertEqual(summary.totalTokens, 50)
        XCTAssertEqual(summary.activeDays, 1)
        XCTAssertEqual(summary.dailyAverageCost, 2.0)
        XCTAssertEqual(summary.peakDay, TokenUsageStats.PeakDay(date: "2026-07-11", cost: 2.0))
        XCTAssertEqual(summary.earliestDate, "2026-07-10")
        XCTAssertEqual(summary.latestDate, "2026-07-12")
    }

    func test_summary_activeDaysZero_dailyAverageIsZero() {
        let records = [
            record("2026-07-10", "codex", costUsd: 0, tokens: 10),
            record("2026-07-11", "claude", costUsd: nil, tokens: 20),
        ]

        let summary = TokenUsageStats.summary(records: records)

        XCTAssertEqual(summary.activeDays, 0)
        XCTAssertEqual(summary.dailyAverageCost, 0)
        XCTAssertEqual(summary.totalCost, 0)
        XCTAssertEqual(summary.totalTokens, 30)
    }

    // MARK: - byProvider

    func test_byProvider_emptyInput_returnsEmpty() {
        XCTAssertEqual(TokenUsageStats.byProvider(records: []), [])
    }

    func test_byProvider_singleProvider_fullShare() {
        let records = [
            record("2026-07-10", "codex", costUsd: 1.5, tokens: 15),
            record("2026-07-11", "codex", costUsd: 0.5, tokens: 5),
        ]

        let result = TokenUsageStats.byProvider(records: records)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].provider, "codex")
        XCTAssertEqual(result[0].totalCost, 2.0)
        XCTAssertEqual(result[0].totalTokens, 20)
        XCTAssertEqual(result[0].activeDays, 2)
        XCTAssertEqual(result[0].costShare, 1.0)
    }

    func test_byProvider_multiProvider_costSharesSumToOne_andSortedByCostThenName() {
        let records = [
            record("2026-07-10", "claude", costUsd: 3.0, tokens: 30),
            record("2026-07-10", "codex", costUsd: 1.0, tokens: 10),
            record("2026-07-11", "gemini", costUsd: 1.0, tokens: 5),
            record("2026-07-12", "claude", costUsd: 1.0, tokens: 10),
        ]

        let result = TokenUsageStats.byProvider(records: records)

        XCTAssertEqual(result.map(\.provider), ["claude", "codex", "gemini"])
        XCTAssertEqual(result[0].totalCost, 4.0)
        XCTAssertEqual(result[1].totalCost, 1.0)
        XCTAssertEqual(result[2].totalCost, 1.0)

        // Same cost: dictionary order (codex before gemini)
        XCTAssertEqual(result[1].provider, "codex")
        XCTAssertEqual(result[2].provider, "gemini")

        let shareSum = result.reduce(0.0) { $0 + $1.costShare }
        XCTAssertEqual(shareSum, 1.0, accuracy: 1e-12)

        XCTAssertEqual(result[0].costShare, 4.0 / 6.0, accuracy: 1e-12)
        XCTAssertEqual(result[1].costShare, 1.0 / 6.0, accuracy: 1e-12)
        XCTAssertEqual(result[2].costShare, 1.0 / 6.0, accuracy: 1e-12)

        XCTAssertEqual(result[0].activeDays, 2)
        XCTAssertEqual(result[1].activeDays, 1)
        XCTAssertEqual(result[2].activeDays, 1)
    }

    func test_byProvider_zeroGrandTotal_costShareIsZero() {
        let records = [
            record("2026-07-10", "codex", costUsd: 0, tokens: 1),
            record("2026-07-11", "claude", costUsd: nil, tokens: 2),
        ]

        let result = TokenUsageStats.byProvider(records: records)

        XCTAssertTrue(result.allSatisfy { $0.costShare == 0 })
        XCTAssertEqual(result.map(\.provider), ["claude", "codex"], "name order when costs equal")
    }

    func test_byProvider_nilFields_treatedAsZero() {
        let records = [
            record("2026-07-10", "codex", costUsd: nil, tokens: nil),
            record("2026-07-11", "codex", costUsd: 2.0, tokens: nil),
        ]

        let result = TokenUsageStats.byProvider(records: records)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].totalCost, 2.0)
        XCTAssertEqual(result[0].totalTokens, 0)
        XCTAssertEqual(result[0].activeDays, 1)
        XCTAssertEqual(result[0].costShare, 1.0)
    }

    // MARK: - dailyRows

    func test_dailyRows_emptyInput_returnsEmpty() {
        XCTAssertEqual(TokenUsageStats.dailyRows(records: []), [])
    }

    func test_dailyRows_sortsByDateDesc_thenCostDesc_thenProviderName() {
        let records = [
            record("2026-07-10", "codex", costUsd: 5.0, tokens: 50),
            record("2026-07-12", "claude", costUsd: 1.0, tokens: 10),
            record("2026-07-12", "codex", costUsd: 3.0, tokens: 30),
            record("2026-07-12", "gemini", costUsd: 3.0, tokens: 20),
            record("2026-07-11", "claude", costUsd: 2.0, tokens: 20),
        ]

        let rows = TokenUsageStats.dailyRows(records: records)

        XCTAssertEqual(rows.map { "\($0.date):\($0.provider):\($0.costUsd)" }, [
            "2026-07-12:codex:3.0",
            "2026-07-12:gemini:3.0",
            "2026-07-12:claude:1.0",
            "2026-07-11:claude:2.0",
            "2026-07-10:codex:5.0",
        ])
    }

    func test_dailyRows_nilFields_becomeZero() {
        let records = [
            record("2026-07-10", "codex", costUsd: nil, tokens: nil),
        ]

        let rows = TokenUsageStats.dailyRows(records: records)

        XCTAssertEqual(rows, [
            TokenUsageStats.DailyRow(date: "2026-07-10", provider: "codex", costUsd: 0, tokens: 0),
        ])
    }

    // MARK: - Helpers

    private func record(
        _ date: String,
        _ provider: String,
        costUsd: Double?,
        tokens: Int?) -> TokenDailyRecord
    {
        TokenDailyRecord(date: date, provider: provider, costUsd: costUsd, tokens: tokens)
    }
}
