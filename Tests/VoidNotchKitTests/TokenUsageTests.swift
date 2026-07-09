import XCTest
@testable import VoidNotchKit

final class TokenUsageTests: XCTestCase {
    func test_percentage_clamps_and_rounds() {
        XCTAssertEqual(ProviderUsage.percentage(sessionTokens: 50, totalTokens: 200), 25)
        XCTAssertEqual(ProviderUsage.percentage(sessionTokens: 300, totalTokens: 200), 100) // clamp 上限
        XCTAssertEqual(ProviderUsage.percentage(sessionTokens: nil, totalTokens: 200), 0)
        XCTAssertEqual(ProviderUsage.percentage(sessionTokens: 50, totalTokens: 0), 0)
    }

    func test_abbreviated_tokens_via_primary_metric() {
        XCTAssertEqual(ProviderUsage(provider: .claude, sessionTokens: 999).primaryMetricText, "999")
        XCTAssertEqual(ProviderUsage(provider: .claude, sessionTokens: 1_500).primaryMetricText, "1.5K")
        XCTAssertEqual(ProviderUsage(provider: .claude, sessionTokens: 2_000_000).primaryMetricText, "2.0M")
    }

    func test_token_text_formatting_for_app_views() {
        let usage = ProviderUsage(
            provider: .claude,
            sessionTokens: 1_500,
            last30DaysTokens: 2_000_000)

        XCTAssertEqual(usage.sessionTokensText, "1.5K")
        XCTAssertEqual(usage.last30DaysTokensText, "2.0M")
        XCTAssertEqual(ProviderUsage(provider: .claude).sessionTokensText, "-")
    }

    func test_cost_text_currency_formatting() {
        XCTAssertEqual(ProviderUsage(provider: .codex, sessionCostUSD: 12.5).sessionCostText, "$12.50")
        XCTAssertEqual(ProviderUsage(provider: .codex, sessionCostUSD: 3, currencyCode: "EUR").sessionCostText, "EUR 3.00")
        XCTAssertEqual(ProviderUsage(provider: .codex).sessionCostText, "-")
    }

    func test_usage_window_clamps_percentages() {
        let w = ProviderUsageWindow(id: "x", title: "5h", kind: .fiveHour,
                                    usedPercent: 150, remainingPercent: -10)
        XCTAssertEqual(w.usedPercent, 100)
        XCTAssertEqual(w.remainingPercent, 0)
    }

    func test_reset_description_spacing_is_normalized() {
        let window = ProviderUsageWindow(
            id: "w",
            title: "Weekly",
            kind: .weekly,
            usedPercent: 69,
            remainingPercent: 31,
            resetDescription: "ResetsJun25at11pm(Asia/Taipei)")

        XCTAssertEqual(window.resetDescription, "Resets Jun 25 at 11pm(Asia/Taipei)")
        XCTAssertEqual(window.resetText, "Resets Jun 25 at 11pm(Asia/Taipei)")
    }

    func test_primary_window_prefers_known_usage() {
        let unknown = ProviderUsageWindow(id: "a", title: "A", kind: .other,
                                          usedPercent: 0, remainingPercent: 0, usageKnown: false)
        let known = ProviderUsageWindow(id: "b", title: "B", kind: .weekly,
                                        usedPercent: 20, remainingPercent: 80, usageKnown: true)
        let usage = ProviderUsage(provider: .antigravity, usageWindows: [unknown, known])
        XCTAssertEqual(usage.primaryWindow?.id, "b")
    }

    func test_sorted_windows_by_rank() {
        let weekly = ProviderUsageWindow(id: "w", title: "Weekly", kind: .weekly,
                                         usedPercent: 0, remainingPercent: 0)
        let fiveHour = ProviderUsageWindow(id: "h", title: "5h", kind: .fiveHour,
                                           usedPercent: 0, remainingPercent: 0)
        let usage = ProviderUsage(provider: .claude, usageWindows: [weekly, fiveHour])
        XCTAssertEqual(usage.sortedUsageWindows.map(\.id), ["h", "w"]) // fiveHour rank 低 → 排前
    }

    func test_copilot_is_available_in_default_provider_list() {
        XCTAssertTrue(TokenProviderKind.defaultVisible.contains(.copilot))
        XCTAssertTrue(TokenProviderKind.copilot.supportsLiveUsageSnapshot)
        XCTAssertTrue(TokenProviderKind.copilot.supportsQuotaSnapshot)
    }

    func test_grok_is_visible_with_live_usage_adapter() {
        XCTAssertTrue(TokenProviderKind.defaultVisible.contains(.grok))
        XCTAssertTrue(TokenProviderKind.grok.supportsLiveUsageSnapshot)
        XCTAssertFalse(TokenProviderKind.grok.supportsCostSnapshot)
        XCTAssertFalse(TokenProviderKind.grok.supportsQuotaSnapshot)
        XCTAssertEqual(TokenProviderKind.grok.settingsBadge, "live")
        XCTAssertEqual(TokenProviderKind.grok.displayName, "Grok")
        XCTAssertEqual(TokenProviderKind.grok.settingsDetail, "Grok credits via CLI/web billing")
    }
}
