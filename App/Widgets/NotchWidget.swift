//
//  NotchWidget.swift — widget 註冊契約
//
//  ⚠️ 此檔依賴 SwiftUI，須以 Xcode app target 編譯（見 docs/research/dynamicnotchkit-spike.md §5）。
//  本機（CommandLineTools）不編譯 App/。
//
//  解 boring.notch 的硬編碼缺陷：widget 不再寫死在巨型 if-else，而是實作此 protocol 後註冊。
//

import SwiftUI
import VoidNotchKit

public protocol NotchWidget: Identifiable {
    var id: String { get }
    /// 收合狀態顯示優先權（高者優先佔用瀏海兩側窄條）。
    var priority: Int { get }
    /// compact 條是否有內容；EmptyView 型 widget 回 false，避免 HStack 為零尺寸子視圖插 spacing。
    var hasCompactContent: Bool { get }

    /// 收合：notch 兩側窄條（密度預算每側 ~80–160pt，見 spike §7）。
    @ViewBuilder func compactView() -> AnyView
    /// 展開：詳細面板。
    @ViewBuilder func expandedView() -> AnyView

    /// 收合時偏好的瀏海側別（可由設定覆寫，見 UserDefaults side key）。
    var preferredSide: NotchSide { get }
}

public extension NotchWidget {
    var hasCompactContent: Bool { true }

    var preferredSide: NotchSide {
        if let raw = UserDefaults.standard.string(forKey: NotchCompactPreferenceKey.side(id)),
           let side = NotchSide(rawValue: raw)
        {
            return side
        }
        return defaultSide(forWidgetID: id)
    }

    var settingsTitle: String {
        switch id {
        case "system": return "System Metrics"
        case "token": return "Model Usage"
        case "agent-activity": return "Agent Activity"
        case "launchd-schedule": return "Scheduled Jobs"
        default: return id
        }
    }

    var settingsSubtitle: String {
        switch id {
        case "system": return "CPU, memory, and thermal readings"
        case "token": return "Token, quota, and cost provider cards"
        case "agent-activity": return "Recent Codex, Claude, and Gemini work events"
        case "launchd-schedule": return "launchd schedules across agent harnesses"
        default: return "Custom widget"
        }
    }

    var settingsIconSystemName: String {
        switch id {
        case "system": return "cpu"
        case "token": return "chart.bar.xaxis"
        case "agent-activity": return "waveform.path.ecg"
        case "launchd-schedule": return "calendar.badge.clock"
        default: return "square.grid.2x2"
        }
    }

    var isRequiredInSettings: Bool {
        id == "system"
    }
}
