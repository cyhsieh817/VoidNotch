//
//  AppUpdateInfo.swift — 更新資訊與版本比較
//

import Foundation

/// 靜態更新端點回傳的最新版本資訊。
public struct AppUpdateInfo: Sendable, Equatable, Codable {
    public var version: String
    public var url: String
    public var notes: String?

    public init(version: String, url: String, notes: String? = nil) {
        self.version = version
        self.url = url
        self.notes = notes
    }
}

/// 僅比較數字版本段，避免字串排序造成 0.10 小於 0.9 的誤判。
public enum SemverCompare {
    /// 回傳 remote 是否比 local 新；解析失敗時採安全側回傳 false。
    public static func isNewer(remote: String, than local: String) -> Bool {
        guard let remoteParts = parse(remote), let localParts = parse(local) else {
            return false
        }

        for (remotePart, localPart) in zip(remoteParts, localParts) {
            if remotePart != localPart {
                return remotePart > localPart
            }
        }
        return false
    }

    private static func parse(_ raw: String) -> [Int]? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") {
            value.removeFirst()
        }
        if let suffixStart = value.firstIndex(of: "-") {
            value = String(value[..<suffixStart])
        }

        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        guard parts.allSatisfy({ part in
            !part.isEmpty && part.allSatisfy { character in
                character >= "0" && character <= "9"
            }
        }) else {
            return nil
        }

        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else {
            return nil
        }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
}
