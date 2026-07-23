//
//  ThermalReaderTests.swift — 溫度 reader（best-effort，容忍無感測器）
//

import XCTest
@testable import SystemMonitor

final class ThermalReaderTests: XCTestCase {

    func testEmptySensorDictionaryProducesEmptySnapshot() {
        let snapshot = thermalSnapshot(from: [:])

        XCTAssertNil(snapshot.cpu)
        XCTAssertNil(snapshot.gpu)
        XCTAssertNil(snapshot.soc)
    }

    func testDedicatedSensorClassification() {
        let snapshot = thermalSnapshot(from: [
            "pACC0": 40,
            "eACC0": 44,
            "GPU0": 50,
            "SOC0": 54,
        ])

        XCTAssertEqual(snapshot.cpu, 42)
        XCTAssertEqual(snapshot.gpu, 50)
        XCTAssertEqual(snapshot.soc, 54)
    }

    func testPMUTdieSensorsAreCPUFallback() {
        let snapshot = thermalSnapshot(from: [
            "PMU tdie0": 46,
            "PMU tdie12": 50,
        ])

        XCTAssertEqual(snapshot.cpu, 48)
    }

    func testDedicatedCPUSensorsTakePriorityOverPMUTdieFallback() {
        let snapshot = thermalSnapshot(from: [
            "pACC0": 40,
            "eACC0": 44,
            "PMU tdie0": 90,
        ])

        XCTAssertEqual(snapshot.cpu, 42)
    }

    func testUnrelatedAndMalformedTemperatureSensorsAreExcludedFromCPU() {
        let snapshot = thermalSnapshot(from: [
            "PMU tdie": 60,
            "prefix PMU tdie0": 61,
            "PMU tdie0 extra": 61,
            "PMU tdie0\n": 61,
            "PMU tdie０": 61,
            "PMU tdie٠": 61,
            "PMU tcal0": 62,
            "gas gauge battery": 63,
            "NAND": 64,
        ])

        XCTAssertNil(snapshot.cpu)
    }

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
