//
//  AppLanguage.swift — UI 語言偏好
//
//  輕量 in-app 切換（非 .strings bundle）：view 以 @AppStorage 讀 rawValue，
//  切換即時生效、不需重啟。字串表在 App 層（App/Theme/L10n.swift）。
//

import Foundation

public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case zhTW = "zh-TW"
    case en = "en"

    /// UserDefaults key，App 層 @AppStorage 與狀態列選單共用。
    public static let preferenceKey = "VoidNotch.language"

    public static let `default`: AppLanguage = .en

    public var id: String { rawValue }

    /// 語言切換器上的顯示名。
    public var pickerLabel: String {
        switch self {
        case .zhTW: return "繁體中文"
        case .en: return "English"
        }
    }

    /// 從偏好原始值解析；nil 或未知值回預設語言。
    public static func resolve(_ rawValue: String?) -> AppLanguage {
        rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .default
    }
}
