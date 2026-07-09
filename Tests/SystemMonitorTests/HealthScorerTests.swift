import XCTest
@testable import SystemMonitor

final class HealthScorerTests: XCTestCase {
    func test_excellent_when_idle() {
        let h = HealthScorer.score(
            cpuPercent: 10,
            memoryPercent: 40,
            memoryPressure: .normal,
            diskUsedPercent: 50,
            diskIOMBps: 5,
            cpuTempC: 45,
            battery: BatteryStatus(),
            uptimeSeconds: 3_600)
        XCTAssertGreaterThanOrEqual(h.score, 85)
        XCTAssertEqual(h.label, "Excellent")
        XCTAssertTrue(h.issues.isEmpty)
    }

    func test_penalizes_high_cpu_and_disk() {
        let h = HealthScorer.score(
            cpuPercent: 95,
            memoryPercent: 50,
            memoryPressure: .normal,
            diskUsedPercent: 96,
            diskIOMBps: 200,
            cpuTempC: 90,
            battery: BatteryStatus(),
            uptimeSeconds: 3_600)
        XCTAssertLessThan(h.score, 65)
        XCTAssertTrue(h.issues.contains("High CPU"))
        XCTAssertTrue(h.issues.contains("Disk Almost Full"))
    }

    func test_memory_pressure_critical() {
        let h = HealthScorer.score(
            cpuPercent: 20,
            memoryPercent: 60,
            memoryPressure: .critical,
            diskUsedPercent: 40,
            diskIOMBps: 1,
            cpuTempC: nil,
            battery: BatteryStatus(),
            uptimeSeconds: 100)
        XCTAssertTrue(h.issues.contains("Critical Memory"))
        XCTAssertLessThan(h.score, 100)
    }

    func test_skips_nil_thermal() {
        let withNil = HealthScorer.score(
            cpuPercent: 20, memoryPercent: 40, memoryPressure: .normal,
            diskUsedPercent: 40, diskIOMBps: 1, cpuTempC: nil,
            battery: BatteryStatus(), uptimeSeconds: 100)
        let withCool = HealthScorer.score(
            cpuPercent: 20, memoryPercent: 40, memoryPressure: .normal,
            diskUsedPercent: 40, diskIOMBps: 1, cpuTempC: 40,
            battery: BatteryStatus(), uptimeSeconds: 100)
        XCTAssertEqual(withNil.score, withCool.score)
    }
}
