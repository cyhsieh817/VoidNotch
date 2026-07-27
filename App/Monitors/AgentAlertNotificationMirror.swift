//
//  AgentAlertNotificationMirror.swift — 代答卡系統通知鏡像
//
//  人不在螢幕前會直接錯過瀏海彈出的問答卡。這支只做一件事：把「有卡片等你作答」
//  與「卡片逾時、已放行回終端機」鏡射成一則系統通知，讓人離開座位也能被叫回來。
//
//  隱私邊界：通知內容只含 provider 與 title／header 摘要，不含 workspace 路徑或
//  完整問題內文——比照 AgentSpeechMessage 的朗讀安全邊界
//  （見 Sources/VoidNotchKit/Audio/AgentSpeechMessage.swift）。
//
//  預設關閉；使用者在 Settings > Alerts > 問答卡 開啟開關的當下才觸發系統授權請求，
//  被拒絕就靜默不發，不重複跳出系統授權對話框騷擾使用者
//  （授權狀態一律以 getNotificationSettings 現查現用，不自行快取「已被拒絕」，
//  一旦使用者事後去系統偏好設定重新放行也能立刻生效）。
//

import Foundation
import UserNotifications
import VoidNotchKit

@MainActor
public final class AgentAlertNotificationMirror {
    public static let shared = AgentAlertNotificationMirror()

    /// 一旦問過就不再主動問第二次；即使使用者拒絕也一樣——重複跳系統授權對話框沒有意義，
    /// macOS 本身也會自動吞掉，這裡持久化只是不讓我方邏輯每次開關都白跑一趟。
    private static let authorizationRequestedKey = "VoidNotch.agentAlert.notificationMirror.authorizationRequested"

    private let center: UNUserNotificationCenter
    private let userDefaults: UserDefaults
    private let preferences: AgentAlertCardPreferences

    init(
        center: UNUserNotificationCenter = .current(),
        userDefaults: UserDefaults = .standard)
    {
        self.center = center
        self.userDefaults = userDefaults
        self.preferences = AgentAlertCardPreferences(userDefaults: userDefaults)
    }

    /// Settings 開關「打開」的當下呼叫（不是每次要發通知時呼叫）。
    public func requestAuthorizationIfNeeded() {
        guard !userDefaults.bool(forKey: Self.authorizationRequestedKey) else { return }
        userDefaults.set(true, forKey: Self.authorizationRequestedKey)
        Task { [weak self] in
            _ = try? await self?.center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// 瀏海彈出可作答卡（`inputRequest` 路徑）時呼叫；`questionSummary` 應傳第一題的
    /// `header`（短摘要），呼叫端不得傳完整 `question` 內文或 workspace 路徑。
    public func postInputRequestNotification(provider: String, title: String, questionSummary: String?) {
        let l10n = Self.currentL10n
        post(
            title: l10n.agentAlertNotificationInputRequestTitle(provider),
            body: l10n.agentAlertNotificationInputRequestBody(title: title, questionSummary: questionSummary),
            identifier: "agentAlert.inputRequest")
    }

    /// 卡片逾時自動 dismiss、放行回終端機時呼叫。使用者手動作答或手動關閉卡片不得呼叫這支。
    public func postReleasedNotification(provider: String) {
        let l10n = Self.currentL10n
        post(
            title: l10n.agentAlertNotificationReleasedTitle(provider),
            body: l10n.agentAlertNotificationReleasedBody,
            identifier: "agentAlert.released")
    }

    private func post(title: String, body: String, identifier: String) {
        guard preferences.notificationMirrorEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            // 現查現用，不快取「已授權/已拒絕」：使用者事後去系統偏好設定改動也要立刻反映。
            let settings = await self.center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            else { return }
            self.deliver(title: title, body: body, identifier: identifier)
        }
    }

    private func deliver(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // identifier 前綴方便除錯辨識來源；UUID 尾碼避免系統把連續兩則同類通知合併/取代。
        let request = UNNotificationRequest(
            identifier: "\(identifier).\(UUID().uuidString)",
            content: content,
            trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    private static var currentL10n: L10n {
        L10n(AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)))
    }
}
