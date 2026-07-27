import Foundation
import XCTest
@testable import VoidNotchKit

final class ProviderUsageFreshnessTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_statusDetailText_now_appends_age_for_stale_usage() {
        let usage = ProviderUsage(
            provider: .codex,
            status: .unavailable,
            errorMessage: "Cached provider data",
            freshness: .stale(lastSuccessAt: now.addingTimeInterval(-2 * 60 * 60)))

        XCTAssertEqual(
            usage.statusDetailText(now: now),
            "Cached provider data · last updated 2h ago")
    }

    func test_statusDetailText_now_matches_existing_property_when_fresh() {
        let usage = ProviderUsage(
            provider: .codex,
            status: .available,
            usedPercent: 25,
            freshness: .fresh)

        XCTAssertEqual(usage.statusDetailText(now: now), usage.statusDetailText)
    }

    func test_providerActionHint_now_returns_authentication_message() {
        XCTAssertEqual(
            usage(with: .authentication).providerActionHint(now: now),
            "Sign in to this provider again, then refresh.")
    }

    func test_providerActionHint_now_returns_rate_limit_message() {
        XCTAssertEqual(
            usage(with: .rateLimited).providerActionHint(now: now),
            "Rate limited by the provider. VoidNotch will retry automatically.")
    }

    func test_providerActionHint_now_returns_schema_drift_message() {
        XCTAssertEqual(
            usage(with: .schemaDrift).providerActionHint(now: now),
            "The provider changed its response format. Showing the last known values.")
    }

    private func usage(with kind: UsageFetchFailureKind) -> ProviderUsage {
        ProviderUsage(
            provider: .codex,
            status: .unavailable,
            errorMessage: "raw provider error",
            diagnosis: UsageFetchDiagnosis(kind: kind, observedAt: now))
    }
}
