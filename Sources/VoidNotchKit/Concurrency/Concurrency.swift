import Foundation

/// 並行套用 transform,但回傳順序對齊輸入順序(以 index 排序還原)。
/// 用於把原本序列 await 的多 provider 抓取改成並行,延遲由「總和」降到「最慢單一」。
public func mapConcurrentlyPreservingOrder<Element: Sendable, Result: Sendable>(
    _ elements: [Element],
    _ transform: @escaping @Sendable (Element) async -> Result
) async -> [Result] {
    guard !elements.isEmpty else { return [] }
    return await withTaskGroup(of: (Int, Result).self) { group in
        for (index, element) in elements.enumerated() {
            group.addTask { (index, await transform(element)) }
        }

        var results = Array<Result?>(repeating: nil, count: elements.count)
        for await (index, result) in group {
            results[index] = result
        }

        return results.enumerated().map { index, result in
            guard let result else {
                preconditionFailure("Missing concurrent map result at index \(index)")
            }
            return result
        }
    }
}
