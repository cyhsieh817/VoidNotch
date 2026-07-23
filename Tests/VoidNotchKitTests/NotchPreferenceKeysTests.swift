import XCTest
@testable import VoidNotchKit

final class NotchPreferenceKeysTests: XCTestCase {
    func test_widget_enabled_key_matches_historical_literal() {
        // Regression lock: must not break existing user defaults.
        XCTAssertEqual(
            NotchWidgetPreferenceKey.enabled("agent-activity"),
            "VoidNotch.widget.agent-activity.enabled")
    }

    func test_widget_enabled_key_format_for_other_ids() {
        XCTAssertEqual(
            NotchWidgetPreferenceKey.enabled("system"),
            "VoidNotch.widget.system.enabled")
        XCTAssertEqual(
            NotchWidgetPreferenceKey.enabled("token"),
            "VoidNotch.widget.token.enabled")
    }

    func test_compact_preference_key_literals_stable() {
        XCTAssertEqual(NotchCompactPreferenceKey.leadingPinned, "VoidNotch.compact.leadingPinned")
        XCTAssertEqual(NotchCompactPreferenceKey.trailingPinned, "VoidNotch.compact.trailingPinned")
        XCTAssertEqual(NotchCompactPreferenceKey.leadingMaxWidth, "VoidNotch.compact.leadingMaxWidth")
        XCTAssertEqual(NotchCompactPreferenceKey.trailingMaxWidth, "VoidNotch.compact.trailingMaxWidth")
        XCTAssertEqual(NotchCompactPreferenceKey.contentHeight, "VoidNotch.compact.contentHeight")
    }

    func test_side_and_maxWidthKey_helpers() {
        XCTAssertEqual(
            NotchCompactPreferenceKey.side("agent-activity"),
            "VoidNotch.widget.agent-activity.side")
        XCTAssertEqual(
            NotchCompactPreferenceKey.maxWidthKey(for: .leading),
            NotchCompactPreferenceKey.leadingMaxWidth)
        XCTAssertEqual(
            NotchCompactPreferenceKey.maxWidthKey(for: .trailing),
            NotchCompactPreferenceKey.trailingMaxWidth)
    }
}
