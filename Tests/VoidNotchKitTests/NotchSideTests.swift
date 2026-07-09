import XCTest
@testable import VoidNotchKit

final class NotchSideTests: XCTestCase {
    func test_default_widget_side() {
        XCTAssertEqual(defaultSide(forWidgetID: "system"), .leading)
        XCTAssertEqual(defaultSide(forWidgetID: "token"), .trailing)
        XCTAssertEqual(defaultSide(forWidgetID: "agent-activity"), .trailing)
        XCTAssertEqual(defaultSide(forWidgetID: "anything-else"), .trailing)
    }

    func test_token_and_agent_default_side_remains_trailing_in_kit() {
        XCTAssertEqual(defaultSide(forWidgetID: "token"), .trailing)
        XCTAssertEqual(defaultSide(forWidgetID: "agent-activity"), .trailing)
    }

    func test_side_raw_values_stable() {
        XCTAssertEqual(NotchSide.leading.rawValue, "leading")
        XCTAssertEqual(NotchSide.trailing.rawValue, "trailing")
        XCTAssertEqual(NotchSide(rawValue: "leading"), .leading)
    }

    func test_compact_layout_clamps_width_and_height() {
        XCTAssertEqual(NotchCompactLayout.clampWidth(10), NotchCompactLayout.minWidth)
        XCTAssertEqual(NotchCompactLayout.clampWidth(999), NotchCompactLayout.maxWidth)
        XCTAssertEqual(NotchCompactLayout.clampWidth(120), 120)
        XCTAssertEqual(NotchCompactLayout.clampHeight(1), NotchCompactLayout.minHeight)
        XCTAssertEqual(NotchCompactLayout.clampHeight(100), NotchCompactLayout.maxHeight)
        XCTAssertEqual(NotchCompactLayout.defaultWidth(for: .leading), 150)
        XCTAssertEqual(NotchCompactLayout.defaultWidth(for: .trailing), 110)
    }

    func test_system_metric_defaults_and_compact_floor() {
        let suite = "VoidNotch.Tests.SystemMetrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        SystemMetricPreferences.registerDefaults(defaults)
        XCTAssertTrue(SystemMetricPreferences.isEnabled(.cpu, defaults: defaults))
        XCTAssertTrue(SystemMetricPreferences.isEnabled(.network, defaults: defaults))

        // Disable all compact metrics except cpu — cannot disable the last one.
        for kind in SystemMetricKind.compactOrder where kind != .cpu {
            SystemMetricPreferences.setEnabled(kind, false, defaults: defaults)
        }
        XCTAssertFalse(SystemMetricPreferences.canDisable(.cpu, defaults: defaults))
        XCTAssertEqual(SystemMetricPreferences.enabledCompactMetrics(defaults: defaults), [.cpu])

        SystemMetricPreferences.setEnabled(.disk, true, defaults: defaults)
        XCTAssertTrue(SystemMetricPreferences.canDisable(.cpu, defaults: defaults))
        XCTAssertEqual(
            SystemMetricPreferences.enabledCompactMetrics(defaults: defaults),
            [.cpu, .disk])
    }
}
