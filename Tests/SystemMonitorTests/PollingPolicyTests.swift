//
//  PollingPolicyTests.swift — Task B2 自適應輪詢策略測試
//

import XCTest
@testable import SystemMonitor

final class PollingPolicyTests: XCTestCase {
    func test_polling_interval_by_activity_level() {
        XCTAssertEqual(SystemMonitorManager.pollingInterval(for: .foreground), 1.0)
        XCTAssertEqual(SystemMonitorManager.pollingInterval(for: .background), 3.0)
        XCTAssertEqual(SystemMonitorManager.pollingInterval(for: .idle), 10.0)
    }

    func test_intervals_respect_minimum() {
        // 所有對照值都不得低於下限。
        for level in [MonitorActivityLevel.foreground, .background, .idle] {
            let interval = SystemMonitorManager.pollingInterval(for: level)
            XCTAssertEqual(SystemMonitorManager.clampedPollingInterval(interval), interval)
        }
    }
}
