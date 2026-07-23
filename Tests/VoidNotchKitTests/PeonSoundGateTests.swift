import XCTest
@testable import VoidNotchKit

final class PeonSoundGateTests: XCTestCase {
    private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func test_sameCategoryThrottledTenSeconds() {
        let gate = PeonSoundGate()
        XCTAssertTrue(gate.shouldPlay(status: .completed, at: t(0)))
        XCTAssertFalse(gate.shouldPlay(status: .completed, at: t(3)))
        XCTAssertTrue(gate.shouldPlay(status: .completed, at: t(11)))
    }

    func test_differentCategoriesIndependent() {
        let gate = PeonSoundGate()
        XCTAssertTrue(gate.shouldPlay(status: .completed, at: t(0)))
        XCTAssertTrue(gate.shouldPlay(status: .started, at: t(1)))
    }

    func test_highPriorityPassesThroughTenSecondWindow() {
        let gate = PeonSoundGate()
        XCTAssertTrue(gate.shouldPlay(status: .needsInput, at: t(0)))
        // completed 剛播不影響 needsInput；needsInput 4 秒後（>2 秒地板）仍可響
        XCTAssertTrue(gate.shouldPlay(status: .completed, at: t(1)))
        XCTAssertTrue(gate.shouldPlay(status: .needsInput, at: t(4)))
    }

    func test_highPriorityHasTwoSecondFloor() {
        let gate = PeonSoundGate()
        XCTAssertTrue(gate.shouldPlay(status: .needsInput, at: t(0)))
        XCTAssertFalse(gate.shouldPlay(status: .needsInput, at: t(1)))  // 2 秒地板內
        XCTAssertTrue(gate.shouldPlay(status: .needsInput, at: t(2)))
    }
}
