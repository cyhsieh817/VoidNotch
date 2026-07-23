//
//  AgentSpeechPreferences.swift — Agent 事件 TTS 偏好（UI-free）
//
//  預設關閉，避免首次啟動突然出聲。UserDefaults 可注入以便測試。
//

import Foundation

public final class AgentSpeechPreferences {
    public enum Keys {
        public static let enabled = "VoidNotch.agentSpeech.enabled"
        public static let completed = "VoidNotch.agentSpeech.completed"
        public static let needsInput = "VoidNotch.agentSpeech.needsInput"
        public static let failed = "VoidNotch.agentSpeech.failed"
        public static let resourceLimit = "VoidNotch.agentSpeech.resourceLimit"
        public static let speakCompleted = completed
        public static let speakNeedsInput = needsInput
        public static let speakFailed = failed
        public static let speakResourceLimit = resourceLimit
        public static let chineseVoiceIdentifier = "VoidNotch.agentSpeech.chineseVoiceIdentifier"
        public static let englishVoiceIdentifier = "VoidNotch.agentSpeech.englishVoiceIdentifier"
        public static let rate = "VoidNotch.agentSpeech.rate"
    }

    public typealias PreferenceKey = Keys

    public static let defaultRate: Double = 0.48
    public static let minimumRate: Double = 0.35
    public static let maximumRate: Double = 0.62

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// TTS 總開關。未設定時為 `false`（預設關閉）。
    public var enabled: Bool {
        get { userDefaults.bool(forKey: Keys.enabled) }
        set { userDefaults.set(newValue, forKey: Keys.enabled) }
    }

    public var isEnabled: Bool {
        get { enabled }
        set { enabled = newValue }
    }

    /// 各事件的朗讀選擇；未設定的舊偏好以 completed 開啟、其餘新增狀態關閉相容。
    public func speaks(_ status: AgentActivityStatus) -> Bool {
        guard enabled else { return false }
        switch status {
        case .completed:
            return bool(for: Keys.completed, default: true)
        case .needsInput:
            return bool(for: Keys.needsInput, default: false)
        case .failed:
            return bool(for: Keys.failed, default: false)
        case .resourceLimit:
            return bool(for: Keys.resourceLimit, default: false)
        case .started, .running, .stopped:
            return false
        }
    }

    public var speaksCompleted: Bool {
        get { bool(for: Keys.completed, default: true) }
        set { userDefaults.set(newValue, forKey: Keys.completed) }
    }

    public var speaksNeedsInput: Bool {
        get { bool(for: Keys.needsInput, default: false) }
        set { userDefaults.set(newValue, forKey: Keys.needsInput) }
    }

    public var speaksFailed: Bool {
        get { bool(for: Keys.failed, default: false) }
        set { userDefaults.set(newValue, forKey: Keys.failed) }
    }

    public var speaksResourceLimit: Bool {
        get { bool(for: Keys.resourceLimit, default: false) }
        set { userDefaults.set(newValue, forKey: Keys.resourceLimit) }
    }

    public var chineseVoiceIdentifier: String? {
        get {
            let value = userDefaults.string(forKey: Keys.chineseVoiceIdentifier)
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        set {
            if let newValue, !newValue.isEmpty {
                userDefaults.set(newValue, forKey: Keys.chineseVoiceIdentifier)
            } else {
                userDefaults.removeObject(forKey: Keys.chineseVoiceIdentifier)
            }
        }
    }

    public var englishVoiceIdentifier: String? {
        get {
            let value = userDefaults.string(forKey: Keys.englishVoiceIdentifier)
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        set {
            if let newValue, !newValue.isEmpty {
                userDefaults.set(newValue, forKey: Keys.englishVoiceIdentifier)
            } else {
                userDefaults.removeObject(forKey: Keys.englishVoiceIdentifier)
            }
        }
    }

    /// 語速；未設定時 0.48，寫入／讀取皆 clamp 至 0.35...0.62。
    public var rate: Double {
        get {
            guard userDefaults.object(forKey: Keys.rate) != nil else {
                return Self.defaultRate
            }
            return Self.clampedRate(userDefaults.double(forKey: Keys.rate))
        }
        set {
            userDefaults.set(Self.clampedRate(newValue), forKey: Keys.rate)
        }
    }

    public static func clampedRate(_ value: Double) -> Double {
        guard value.isFinite else { return defaultRate }
        return min(max(value, minimumRate), maximumRate)
    }

    private func bool(for key: String, default defaultValue: Bool) -> Bool {
        guard userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.bool(forKey: key)
    }
}
