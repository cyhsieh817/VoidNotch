//
//  ThermalReaderTests.swift — 溫度 reader（best-effort，容忍無感測器）
//

import XCTest
@testable import SystemMonitor

final class ThermalReaderTests: XCTestCase {

    /// 溫度為 best-effort：可能 nil。若有值須落在合理攝氏區間。
    func testTemperaturesWithinSaneRangeIfPresent() {
        let reader = ThermalReader()
        let t = reader.read()
        for value in [t.cpu, t.gpu, t.soc] {
            if let v = value {
                XCTAssertTrue((10.0...120.0).contains(v))
            }
        }

        if t.cpu == nil && t.gpu == nil && t.soc == nil {
            XCTAssertNotNil(reader.lastFailureReason)
        } else {
            XCTAssertNil(reader.lastFailureReason)
        }
    }

    func testReadDoesNotCrashRepeatedly() {
        let reader = ThermalReader()
        for _ in 0..<5 { _ = reader.read() }
    }

    func testManagerSnapshotAggregatesAllLayers() {
        let snap = SystemMonitorManager().snapshot()
        XCTAssertGreaterThan(snap.ram.total, 0)
        XCTAssertEqual(snap.cpu.perCore.count, Sysctl.logicalCPU)
    }
}
