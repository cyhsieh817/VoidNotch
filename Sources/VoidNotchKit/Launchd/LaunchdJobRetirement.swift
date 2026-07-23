import Foundation

/// launchd job 封存與可移除判斷的純邏輯。
public enum LaunchdJobRetirement: Sendable {
    /// 產生沿工作區退役慣例使用的封存檔名。
    public static func archivedFileName(for originalFileName: String, at date: Date) -> String {
        archivedFileName(for: originalFileName, at: date, collisionIndex: 0)
    }

    /// 產生指定碰撞序號的封存檔名；0 表示第一個候選路徑。
    public static func archivedFileName(
        for originalFileName: String,
        at date: Date,
        collisionIndex: Int
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.timeZone = .current

        let fileName = URL(fileURLWithPath: originalFileName).lastPathComponent
        let suffix = collisionIndex == 0 ? "" : ".\(collisionIndex)"
        return "_DELETE_\(formatter.string(from: date))_\(fileName)\(suffix).retired"
    }

    /// 從未占用的封存檔名候選中取第一個可用名稱。
    public static func availableArchivedFileName(
        for originalFileName: String,
        at date: Date,
        occupiedFileNames: Set<String>
    ) -> String? {
        let firstCandidate = archivedFileName(
            for: originalFileName,
            at: date,
            collisionIndex: 0)
        guard occupiedFileNames.contains(firstCandidate) else {
            return firstCandidate
        }

        for collisionIndex in 1...20 {
            let candidate = archivedFileName(
                for: originalFileName,
                at: date,
                collisionIndex: collisionIndex)
            if !occupiedFileNames.contains(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// 檔名是否仍會被 launchd 載入（副檔名為 .plist 即會，前綴無關）。
    public static func isLoadableByLaunchd(fileName: String) -> Bool {
        URL(fileURLWithPath: fileName).pathExtension.lowercased() == "plist"
    }

    /// 只有使用者自己的 LaunchAgents 目錄內、可退役的 job 可以移除。
    public static func isRemovable(
        plistPath: String,
        phase: LaunchdJobPhase,
        homeLaunchAgents: URL,
        isZombie: Bool = false
    ) -> Bool {
        let normalizedPlistPath = URL(fileURLWithPath: plistPath).standardizedFileURL.path
        let normalizedHomePath = homeLaunchAgents.standardizedFileURL.path
        guard normalizedPlistPath.hasPrefix(normalizedHomePath + "/") else { return false }
        return phase != .archived || isZombie
    }
}
