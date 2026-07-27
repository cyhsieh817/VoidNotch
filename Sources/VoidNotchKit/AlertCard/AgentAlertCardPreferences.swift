//
//  AgentAlertCardPreferences.swift — 問答卡外觀／通知偏好（UI-free）
//
//  純邏輯：偏好鍵、字級倍率 clamp。供 App 層 SwiftUI（NotchAgentAlertView／Settings）
//  與系統通知鏡像共用同一份真相，避免各處各寫一套 clamp 規則。
//

import Foundation

public final class AgentAlertCardPreferences {
    public enum Keys {
        /// 問答卡字級倍率（Double）。未設定時視為 `defaultTextScale`。
        public static let textScale = "VoidNotch.agentAlert.textScale"
        /// 代答卡系統通知鏡像總開關（Bool）。預設關閉。
        public static let notificationMirror = "VoidNotch.agentAlert.notificationMirror"
    }

    public static let defaultTextScale: Double = 1.0
    public static let minimumTextScale: Double = 0.8
    public static let maximumTextScale: Double = 1.6

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// 讀取時一律 clamp 至 0.8...1.6；非法值（NaN/Inf）回預設值。
    public static func clampedTextScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTextScale }
        return min(max(value, minimumTextScale), maximumTextScale)
    }

    /// 目前字級倍率；未設定時回預設值 1.0，讀取一律 clamp。
    public var textScale: Double {
        get {
            guard userDefaults.object(forKey: Keys.textScale) != nil else {
                return Self.defaultTextScale
            }
            return Self.clampedTextScale(userDefaults.double(forKey: Keys.textScale))
        }
        set {
            userDefaults.set(Self.clampedTextScale(newValue), forKey: Keys.textScale)
        }
    }

    /// 系統通知鏡像開關；未設定時預設關閉（避免首次啟動突然跳通知）。
    public var notificationMirrorEnabled: Bool {
        get { userDefaults.bool(forKey: Keys.notificationMirror) }
        set { userDefaults.set(newValue, forKey: Keys.notificationMirror) }
    }
}

/// 問答卡字級倍率的四段預設檔位（Settings Picker 用）；`rawValue` 即寫入 UserDefaults 的 Double。
public enum AgentAlertTextScalePreset: Double, CaseIterable, Sendable {
    case small = 0.9
    case standard = 1.0
    case large = 1.2
    case extraLarge = 1.4
}
