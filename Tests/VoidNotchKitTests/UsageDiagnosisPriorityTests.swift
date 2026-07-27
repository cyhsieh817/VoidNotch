import Foundation
import XCTest
@testable import VoidNotchKit

/// Diagnosis priority for cost+live merge:
/// - When live usage is present, only `liveDiagnosis` counts (cost is additive).
/// - When live usage is absent, `costDiagnosis` decides success/failure.
private func resolvedDiagnosis(
    hasLiveUsage: Bool,
    liveDiagnosis: UsageFetchDiagnosis?,
    costDiagnosis: UsageFetchDiagnosis?) -> UsageFetchDiagnosis?
{
    if hasLiveUsage {
        return liveDiagnosis
    }
    return costDiagnosis
}

@MainActor
final class UsageDiagnosisPriorityTests: XCTestCase {
    func test_liveSuccessIgnoresCostNoUsableDataDiagnosis() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let costOnly = UsageFetchDiagnosis(kind: .noUsableData, observedAt: now)

        let resolved = resolvedDiagnosis(
            hasLiveUsage: true,
            liveDiagnosis: nil,
            costDiagnosis: costOnly)

        XCTAssertNil(resolved)
    }

    func test_withoutLiveUsageCostNoUsableDataRemainsFailure() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let costOnly = UsageFetchDiagnosis(kind: .noUsableData, observedAt: now)

        let resolved = resolvedDiagnosis(
            hasLiveUsage: false,
            liveDiagnosis: nil,
            costDiagnosis: costOnly)

        XCTAssertEqual(resolved, costOnly)
    }

    func test_availableUsageWithNilDiagnosisStaysFreshAndResetsFailures() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let provider = DiagnosisPriorityMockProvider(
            usage: ProviderUsage(
                provider: .codex,
                status: .available,
                usedPercent: 17,
                sessionTokens: 170),
            diagnosis: nil)
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: provider,
            now: { now })

        await store.refresh()

        XCTAssertEqual(store.providers.count, 1)
        XCTAssertEqual(store.providers[0].status, .available)
        XCTAssertNil(store.providers[0].diagnosis)
        XCTAssertEqual(store.providers[0].freshness, .fresh)
        XCTAssertTrue(store.providers[0].freshness.isFresh)
        XCTAssertEqual(store.retryState(for: .codex).consecutiveFailures, 0)
        XCTAssertEqual(store.retryState(for: .codex), UsageRetryState())
    }

    func test_nilDiagnosisDoesNotMarkDegradedEvenWithPriorKnownGood() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "UsageDiagnosisPriorityTests-\(UUID().uuidString)-cache.json",
                isDirectory: false)
        let cache = UsageResilienceCache(fileURL: cacheURL)
        cache.recordSuccess(
            ProviderUsage(
                provider: .codex,
                status: .available,
                usedPercent: 9,
                sessionTokens: 90),
            at: now.addingTimeInterval(-300))

        let provider = DiagnosisPriorityMockProvider(
            usage: ProviderUsage(
                provider: .codex,
                status: .available,
                usedPercent: 42,
                sessionTokens: 420),
            diagnosis: nil)
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: provider,
            resilienceCache: cache,
            now: { now })

        await store.refresh()

        XCTAssertEqual(store.providers[0].status, .available)
        XCTAssertNil(store.providers[0].diagnosis)
        XCTAssertEqual(store.providers[0].freshness, .fresh)
        XCTAssertEqual(store.retryState(for: .codex).consecutiveFailures, 0)

        // Quarantine temp cache (no rm).
        let quarantine = FileManager.default.temporaryDirectory
            .appendingPathComponent("tvw", isDirectory: true)
        try? FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let destination = quarantine.appendingPathComponent(
            "_DELETE_\(cacheURL.lastPathComponent)",
            isDirectory: false)
        try? FileManager.default.moveItem(at: cacheURL, to: destination)
    }
}

private final class DiagnosisPriorityMockProvider: TokenUsageProviding, @unchecked Sendable {
    private let usage: ProviderUsage
    private let diagnosis: UsageFetchDiagnosis?

    init(usage: ProviderUsage, diagnosis: UsageFetchDiagnosis?) {
        self.usage = usage
        self.diagnosis = diagnosis
    }

    func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsageFetchResult] {
        providers.map { kind in
            ProviderUsageFetchResult(
                usage: ProviderUsage(
                    provider: kind,
                    status: usage.status,
                    usedPercent: usage.usedPercent,
                    sessionTokens: usage.sessionTokens,
                    last30DaysTokens: usage.last30DaysTokens,
                    sessionCostUSD: usage.sessionCostUSD,
                    last30DaysCostUSD: usage.last30DaysCostUSD,
                    currencyCode: usage.currencyCode,
                    updatedAt: usage.updatedAt,
                    errorMessage: usage.errorMessage,
                    detailText: usage.detailText,
                    usageWindows: usage.usageWindows,
                    sourceLabel: usage.sourceLabel,
                    strategyID: usage.strategyID,
                    accountEmail: usage.accountEmail,
                    accountPlan: usage.accountPlan,
                    cliVersion: usage.cliVersion),
                diagnosis: diagnosis)
        }
    }
}
