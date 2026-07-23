//
//  AgentSpeechMessage.swift — Agent 事件 TTS 文案（UI-free）
//
//  只讀安全的 title／題目／選項；不讀 detail/workspace，避免敏感路徑被公開播出。
//

import Foundation

public enum AgentSpeechLanguage: String, CaseIterable, Sendable {
    case zhTW
    case enUS

    public var languageCode: String {
        switch self {
        case .zhTW: return "zh-TW"
        case .enUS: return "en-US"
        }
    }
}

public struct AgentSpeechMessage: Equatable, Sendable {
    public let text: String
    public let language: AgentSpeechLanguage

    public init(text: String, language: AgentSpeechLanguage) {
        self.text = text
        self.language = language
    }

    /// 舊 API 保留，completed 文案行為不變。
    public static func completion(for event: AgentActivityEvent) -> AgentSpeechMessage? {
        guard event.status == .completed else { return nil }

        let title = normalizeTitle(event.title)
        let language = detectLanguage(in: title)
        let spokenTitle: String
        if title.isEmpty {
            spokenTitle = language == .zhTW ? "任務" : "task"
        } else {
            spokenTitle = title
        }

        let provider = event.provider.displayName
        let text: String
        switch language {
        case .zhTW:
            text = "\(provider) 已完成：\(spokenTitle)"
        case .enUS:
            text = "\(provider) completed: \(spokenTitle)"
        }
        return AgentSpeechMessage(text: text, language: language)
    }

    /// 依事件產生安全且有限長度的朗讀文案；偏好開關由 `AgentSpeechPreferences` 控制。
    public static func event(for event: AgentActivityEvent) -> AgentSpeechMessage? {
        switch event.status {
        case .completed:
            return completion(for: event)
        case .needsInput:
            return needsInput(for: event)
        case .failed:
            return failure(for: event, resourceLimited: false)
        case .resourceLimit:
            return failure(for: event, resourceLimited: true)
        case .started, .running, .stopped:
            return nil
        }
    }

    public static func message(for event: AgentActivityEvent) -> AgentSpeechMessage? {
        Self.event(for: event)
    }

    // MARK: - Private

    private static let maxTitleLength = 240
    private static let maxShortTextLength = 120
    public static let maximumTextLength = 360

    /// 壓縮連續空白／換行為單一空白，trim 後截斷至 240 字元。
    public static func normalizeText(_ raw: String, maximumLength: Int) -> String {
        let collapsed = raw
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if collapsed.count <= maximumLength {
            return collapsed
        }
        return String(collapsed.prefix(maximumLength))
    }

    private static func normalizeTitle(_ raw: String) -> String {
        normalizeText(raw, maximumLength: maxTitleLength)
    }

    private static func needsInput(for event: AgentActivityEvent) -> AgentSpeechMessage? {
        guard let request = event.inputRequest else {
            let language = detectLanguage(in: event.title)
            let text = language == .zhTW
                ? "\(event.provider.displayName) 需要輸入，請回 Agent 終端機作答。"
                : "\(event.provider.displayName) needs input. Please answer in the Agent terminal."
            return bounded(text: text, language: language)
        }

        guard !request.questions.isEmpty,
              request.questions.allSatisfy({
                  AgentSpeechOptionMatcher.isValid(labels: $0.options.map(\.label))
              })
        else { return nil }
        let allLabels = request.questions.flatMap { $0.options.map(\.label) }
        let languageCode = AgentSpeechOptionMatcher.languageCode(
            question: request.questions.map(\.question).joined(separator: " "),
            header: request.questions.map(\.header).joined(separator: " "),
            labels: allLabels)
        let language: AgentSpeechLanguage = languageCode == "zh-TW" ? .zhTW : .enUS
        let questionText = request.questions.map { question in
            let header = normalizeText(question.header, maximumLength: 60)
            let prompt = normalizeText(question.question, maximumLength: maxShortTextLength)
            let optionText = question.options
                .map { normalizeText($0.label, maximumLength: 40) }
                .joined(separator: language == .zhTW ? "、" : ", ")
            return language == .zhTW
                ? "\(header)：\(prompt)。選項：\(optionText)"
                : "\(header): \(prompt). Options: \(optionText)"
        }.joined(separator: language == .zhTW ? "；" : " ")
        let text: String
        if language == .zhTW {
            text = "\(event.provider.displayName) 需要你的選擇。\(questionText)。"
        } else {
            text = "\(event.provider.displayName) needs your choice. \(questionText)."
        }
        return bounded(text: text, language: language)
    }

    private static func failure(for event: AgentActivityEvent, resourceLimited: Bool) -> AgentSpeechMessage? {
        let title = normalizeText(event.title, maximumLength: maxShortTextLength)
        let language = detectLanguage(in: title)
        let safeTitle = title.isEmpty ? (language == .zhTW ? "任務" : "task") : title
        let text: String
        if language == .zhTW {
            text = resourceLimited
                ? "\(event.provider.displayName) 已達資源限制：\(safeTitle)"
                : "\(event.provider.displayName) 失敗：\(safeTitle)"
        } else {
            text = resourceLimited
                ? "\(event.provider.displayName) reached a resource limit: \(safeTitle)"
                : "\(event.provider.displayName) failed: \(safeTitle)"
        }
        return bounded(text: text, language: language)
    }

    private static func bounded(text: String, language: AgentSpeechLanguage) -> AgentSpeechMessage {
        AgentSpeechMessage(
            text: normalizeText(text, maximumLength: maximumTextLength),
            language: language)
    }

    /// 含 CJK Unified Ideographs 或注音（Bopomofo）→ zhTW，否則 enUS。
    private static func detectLanguage(in text: String) -> AgentSpeechLanguage {
        for scalar in text.unicodeScalars {
            if isCJKUnifiedIdeograph(scalar) || isBopomofo(scalar) {
                return .zhTW
            }
        }
        return .enUS
    }

    private static func isCJKUnifiedIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        // CJK Unified Ideographs: U+4E00–U+9FFF
        (0x4E00...0x9FFF).contains(scalar.value)
    }

    private static func isBopomofo(_ scalar: Unicode.Scalar) -> Bool {
        // Bopomofo: U+3100–U+312F；Bopomofo Extended: U+31A0–U+31BF
        (0x3100...0x312F).contains(scalar.value)
            || (0x31A0...0x31BF).contains(scalar.value)
    }
}
