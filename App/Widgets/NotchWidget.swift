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

public enum NotchCompactPreferenceKey {
    /// `true` means the left compact slot is kept visible; `false` means it collapses into the physical notch.
    public static let leadingPinned = "VoidNotch.compact.leadingPinned"
    /// `true` means the right compact slot is kept visible; `false` means it collapses into the physical notch.
    public static let trailingPinned = "VoidNotch.compact.trailingPinned"
    /// Max content width (pt) for leading compact slot.
    public static let leadingMaxWidth = "VoidNotch.compact.leadingMaxWidth"
    /// Max content width (pt) for trailing compact slot.
    public static let trailingMaxWidth = "VoidNotch.compact.trailingMaxWidth"
    /// Compact content height (pt).
    public static let contentHeight = "VoidNotch.compact.contentHeight"

    public static func side(_ widgetID: String) -> String {
        "VoidNotch.widget.\(widgetID).side"
    }

    public static func maxWidthKey(for side: NotchSide) -> String {
        switch side {
        case .leading: return leadingMaxWidth
        case .trailing: return trailingMaxWidth
        }
    }
}

public enum NotchWidgetPreferenceKey {
    public static func enabled(_ id: String) -> String {
        "VoidNotch.widget.\(id).enabled"
    }
}

public protocol NotchWidget: Identifiable {
    var id: String { get }
    /// 收合狀態顯示優先權（高者優先佔用瀏海兩側窄條）。
    var priority: Int { get }

    /// 收合：notch 兩側窄條（密度預算每側 ~80–160pt，見 spike §7）。
    @ViewBuilder func compactView() -> AnyView
    /// 展開：詳細面板。
    @ViewBuilder func expandedView() -> AnyView

    /// 收合時偏好的瀏海側別（可由設定覆寫，見 UserDefaults side key）。
    var preferredSide: NotchSide { get }
}

public extension NotchWidget {
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
        default: return id
        }
    }

    var settingsSubtitle: String {
        switch id {
        case "system": return "CPU, memory, and thermal readings"
        case "token": return "Token, quota, and cost provider cards"
        case "agent-activity": return "Recent Codex, Claude, and Gemini work events"
        default: return "Custom widget"
        }
    }

    var settingsIconSystemName: String {
        switch id {
        case "system": return "cpu"
        case "token": return "chart.bar.xaxis"
        case "agent-activity": return "waveform.path.ecg"
        default: return "square.grid.2x2"
        }
    }

    var isRequiredInSettings: Bool {
        id == "system"
    }
}
