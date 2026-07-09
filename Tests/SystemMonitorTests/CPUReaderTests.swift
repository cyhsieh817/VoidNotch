//
//  CPUReaderTests.swift — CPU reader 對核 sysctl 拓撲
//

import Foundation
import XCTest
@testable import SystemMonitor

final class CPUReaderTests: XCTestCase {

    /// 取兩次（中間 sleep）以產生差分。
    private func sampleTwice() -> CPULoad {
        let reader = CPUReader()
        _ = reader.read()
        Thread.sleep(forTimeInterval: 0.3)
        return reader.read()
    }

    func testPerCoreCountMatchesLogicalCPU() {
        XCTAssertEqual(sampleTwice().perCore.count, Sysctl.logicalCPU)
    }

    func testPerCoreUsageWithinUnitRange() {
        for u in sampleTwice().perCore {
            XCTAssertTrue((0.0...1.0).contains(u))
        }
    }

    func testTotalUsageWithinUnitRange() {
        let load = sampleTwice()
        XCTAssertTrue((0.0...1.0).contains(load.total))
        XCTAssertTrue((0.0...1.0).contains(load.idle))
    }

    func testCoreSplitCountsMatchSysctl() {
        let load = sampleTwice()
        XCTAssertEqual(load.pCoreCount, Sysctl.pCores)
        XCTAssertEqual(load.eCoreCount, Sysctl.eCores)
    }

    func testCoreSplitAveragesPresentOnAppleSilicon() throws {
        try XCTSkipUnless(Sysctl.pCores > 0 && Sysctl.eCores > 0)
        let load = sampleTwice()
        let p = try XCTUnwrap(load.usagePCores)
        let e = try XCTUnwrap(load.usageECores)
        XCTAssertTrue((0.0...1.0).contains(p))
        XCTAssertTrue((0.0...1.0).contains(e))
    }

    func testFirstReadHasZeroDiff() {
        // 首次無前值 → total 為 0（差分基準）
        XCTAssertEqual(CPUReader().read().total, 0)
    }

    func test_core_split_marked_heuristic_until_verified() {
        let load = CPUReader().read()
        XCTAssertTrue(load.coreSplitIsHeuristic, "P/E 分群在真機對照前須標為 heuristic")
    }
}
