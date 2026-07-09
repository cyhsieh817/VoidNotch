import XCTest
@testable import VoidNotchKit

final class ConcurrencyTests: XCTestCase {
    func test_concurrent_map_preserves_input_order() async {
        let input = [0, 1, 2, 3, 4]
        // 後面的 index 故意更早完成;輸出順序仍須對齊輸入順序。
        let output = await mapConcurrentlyPreservingOrder(input) { value in
            try? await Task.sleep(nanoseconds: UInt64((5 - value) * 1_000_000))
            return value * 10
        }
        XCTAssertEqual(output, [0, 10, 20, 30, 40])
    }

    func test_concurrent_map_empty_input() async {
        let output = await mapConcurrentlyPreservingOrder([Int]()) { $0 }
        XCTAssertEqual(output, [])
    }
}
