//
//  RAMReaderTests.swift — RAM reader 對核 sysctl 地面真值
//

import XCTest
@testable import SystemMonitor

final class RAMReaderTests: XCTestCase {

    func testTotalMatchesSysctlMemsize() {
        let ram = RAMReader().read()
        let truth = Double(Sysctl.memSize)
        XCTAssertGreaterThan(truth, 0)
        XCTAssertLessThan(abs(ram.total - truth), 2) // host_info max_mem == hw.memsize
    }

    func testUsageWithinBounds() {
        let ram = RAMReader().read()
        XCTAssertGreaterThan(ram.used, 0)
        XCTAssertGreaterThanOrEqual(ram.free, 0)
        XCTAssertLessThanOrEqual(ram.used, ram.total)
        XCTAssertTrue((0...100).contains(ram.percent))
    }

    func testUsedPlusFreeApproximatesTotal() {
        let ram = RAMReader().read()
        XCTAssertLessThan(abs((ram.used + ram.free) - ram.total), 2)
    }

    func testSwapConsistency() {
        let ram = RAMReader().read()
        XCTAssertGreaterThanOrEqual(ram.swap.total, 0)
        XCTAssertLessThanOrEqual(ram.swap.used, ram.swap.total + 1)
    }

    func testPressureIsKnownLevel() {
        let ram = RAMReader().read()
        XCTAssertNotEqual(ram.pressure, .unknown)
    }
}
