import XCTest
@testable import SystemMonitor

final class DiskNetworkTests: XCTestCase {
    func test_disk_usage_percent_clamp() {
        let d = DiskUsage(mount: "/", totalBytes: 100, freeBytes: 25)
        XCTAssertEqual(d.usedBytes, 75)
        XCTAssertEqual(d.usedPercent, 75)
        XCTAssertEqual(d.freePercent, 25)
    }

    func test_disk_zero_total() {
        let d = DiskUsage(mount: "/", totalBytes: 0, freeBytes: 0)
        XCTAssertEqual(d.usedPercent, 0)
    }

    func test_disk_reader_root_nonzero() {
        let d = DiskReader(path: "/").read()
        XCTAssertEqual(d.mount, "/")
        XCTAssertGreaterThan(d.totalBytes, 0)
        XCTAssertLessThanOrEqual(d.usedPercent, 100)
    }

    func test_disk_io_differential() {
        let reader = DiskIOReader()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let first = reader.read(currentRead: 0, currentWrite: 0, now: t0)
        XCTAssertEqual(first.readMBps, 0)
        let second = reader.read(
            currentRead: 10 * 1_048_576,
            currentWrite: 5 * 1_048_576,
            now: t0.addingTimeInterval(1))
        XCTAssertEqual(second.readMBps, 10, accuracy: 0.01)
        XCTAssertEqual(second.writeMBps, 5, accuracy: 0.01)
    }

    func test_network_differential_and_compact() {
        let reader = NetworkReader()
        let t0 = Date(timeIntervalSince1970: 2_000)
        _ = reader.read(name: "en0", rx: 0, tx: 0, now: t0)
        let second = reader.read(
            name: "en0",
            rx: 2 * 1_048_576,
            tx: 1_048_576,
            now: t0.addingTimeInterval(1))
        XCTAssertEqual(second.rxMBps, 2, accuracy: 0.01)
        XCTAssertEqual(second.txMBps, 1, accuracy: 0.01)
        XCTAssertTrue(second.compactDownText.hasPrefix("↓"))
    }

    func test_network_compact_rate_format() {
        XCTAssertEqual(NetworkUsage.compactRate(0), "0K")
        XCTAssertEqual(NetworkUsage.compactRate(0.05), "51K") // ~0.05 * 1024 ≈ 51
        XCTAssertEqual(NetworkUsage.compactRate(1.2), "1.2M")
    }

    func test_battery_health_labels() {
        XCTAssertEqual(BatteryReader.healthLabel(cycles: 100, capacity: 95), "Healthy")
        XCTAssertEqual(BatteryReader.healthLabel(cycles: 850, capacity: 90), "Fair")
        XCTAssertEqual(BatteryReader.healthLabel(cycles: 950, capacity: 90), "Service Soon")
        XCTAssertEqual(BatteryReader.healthLabel(cycles: 100, capacity: 50), "Service Soon")
    }

    func test_manager_snapshot_has_new_fields() {
        let m = SystemMonitorManager()
        _ = m.snapshot()
        Thread.sleep(forTimeInterval: 0.4)
        let s = m.snapshot()
        XCTAssertGreaterThan(s.disk.totalBytes, 0)
        XCTAssertFalse(s.host.uptimeText.isEmpty)
        XCTAssertGreaterThanOrEqual(s.health.score, 0)
        XCTAssertLessThanOrEqual(s.health.score, 100)
    }
}
