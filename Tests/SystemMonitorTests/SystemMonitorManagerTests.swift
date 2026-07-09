//
//  SystemMonitorManagerTests.swift — manager 行為測試
//

import Foundation
import XCTest
@testable import SystemMonitor

final class SystemMonitorManagerTests: XCTestCase {

    func testPollingIntervalClampsInvalidValues() {
        let minimum = SystemMonitorManager.minimumPollingInterval
        XCTAssertEqual(SystemMonitorManager.clampedPollingInterval(0), minimum)
        XCTAssertEqual(SystemMonitorManager.clampedPollingInterval(-1), minimum)
        XCTAssertEqual(SystemMonitorManager.clampedPollingInterval(.nan), minimum)
        XCTAssertEqual(SystemMonitorManager.clampedPollingInterval(.infinity), minimum)
    }

    func testPollingIntervalKeepsValidValues() {
        XCTAssertEqual(SystemMonitorManager.clampedPollingInterval(1.0), 1.0)
        XCTAssertEqual(SystemMonitorManager.clampedPollingInterval(2.5), 2.5)
    }
}
