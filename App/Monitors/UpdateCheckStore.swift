//
//  UpdateCheckStore.swift — App 更新檢查的狀態包裝
//

import Foundation
import Observation
import VoidNotchKit

@Observable
@MainActor
public final class UpdateCheckStore {
    public private(set) var availableUpdate: AppUpdateInfo?
    public private(set) var isChecking: Bool = false
    public private(set) var lastCheckedAt: Date? = nil

    private static let lastCheckedAtKey = "updateCheck.lastCheckedAt"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private let client: UpdateCheckClient
    public let currentVersion: String
    /// false 時略過一切更新檢查（例如 `swift run` 裸執行檔無 Info.plist）。
    public let isEnabled: Bool

    public init(client: UpdateCheckClient, currentVersion: String, isEnabled: Bool = true) {
        self.client = client
        self.currentVersion = currentVersion
        self.isEnabled = isEnabled
        // 還原既有節流戳記，讓 UI 能顯示「上次檢查」相對時間。
        if UserDefaults.standard.object(forKey: Self.lastCheckedAtKey) != nil {
            let ts = UserDefaults.standard.double(forKey: Self.lastCheckedAtKey)
            lastCheckedAt = Date(timeIntervalSince1970: ts)
        }
    }

    /// 啟動時依 24 小時節流檢查；網路或解析失敗時保持靜默。
    public func checkIfDue(force: Bool = false) async {
        guard isEnabled else { return }
        guard !isChecking else { return }

        let now = Date().timeIntervalSince1970
        if !force,
           UserDefaults.standard.object(forKey: Self.lastCheckedAtKey) != nil,
           now - UserDefaults.standard.double(forKey: Self.lastCheckedAtKey) < Self.checkInterval
        {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let latest = try await client.fetchLatest()
            // 節流戳記只在成功後寫：失敗（斷網/端點掛）下次啟動即重試，不被鎖 24h。
            UserDefaults.standard.set(now, forKey: Self.lastCheckedAtKey)
            lastCheckedAt = Date(timeIntervalSince1970: now)
            availableUpdate = SemverCompare.isNewer(
                remote: latest.version,
                than: currentVersion) ? latest : nil
        } catch {
            // 更新檢查不是 App 主功能，任何失敗都不干擾使用者介面。
        }
    }
}
