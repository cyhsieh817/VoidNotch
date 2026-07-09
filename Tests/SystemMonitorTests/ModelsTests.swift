//
//  ModelsTests.swift — 純模型邏輯
//

import XCTest
@testable import SystemMonitor

final class ModelsTests: XCTestCase {

    func testRamUsageComputation() {
        var ram = RAMUsage()
        ram.total = 16_000_000_000
        ram.free = 4_000_000_000
        XCTAssertLessThan(abs(ram.usage - 0.75), 0.0001)
        XCTAssertEqual(ram.percent, 75)
    }

    func testRamZeroTotalNoDivideByZero() {
        let ram = RAMUsage()
        XCTAssertEqual(ram.usage, 0)
        XCTAssertEqual(ram.percent, 0)
    }

    func testRamAppMemoryNonNegative() {
        var ram = RAMUsage()
        ram.used = 1_000; ram.wired = 800; ram.compressed = 500
        XCTAssertEqual(ram.app, 0) // clamp 至 0，不可為負
    }

    func testCpuPercentRounding() {
        var cpu = CPULoad()
        cpu.total = 0.326
        XCTAssertEqual(cpu.percent, 33)
    }

    func testMemoryPressureRawValues() {
        XCTAssertEqual(MemoryPressure(rawValue: 1), .normal)
        XCTAssertEqual(MemoryPressure(rawValue: 2), .warning)
        XCTAssertEqual(MemoryPressure(rawValue: 4), .critical)
        XCTAssertNil(MemoryPressure(rawValue: 3))
    }

    func testThermalOptionalsDefaultNil() {
        let t = ThermalSnapshot()
        XCTAssertNil(t.cpu)
        XCTAssertNil(t.gpu)
        XCTAssertNil(t.soc)
    }

    func testSnapshotEquatable() {
        // collectedAt is Date() — compare with explicit equal timestamps
        let t = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(SystemSnapshot(collectedAt: t), SystemSnapshot(collectedAt: t))
    }

    func testMemoryPressureLabel() {
        XCTAssertEqual(MemoryPressure.normal.label, "normal")
        XCTAssertEqual(MemoryPressure.critical.label, "critical")
    }

    func testHostUptimeFormatting() {
        var h = HostInfo()
        h.uptimeSeconds = 90
        XCTAssertEqual(h.uptimeText, "1m")
        h.uptimeSeconds = 3_600 + 120
        XCTAssertEqual(h.uptimeText, "1h 2m")
        h.uptimeSeconds = 86_400 * 2 + 3_600
        XCTAssertEqual(h.uptimeText, "2d 1h")
    }
}
