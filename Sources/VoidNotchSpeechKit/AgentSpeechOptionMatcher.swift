//
//  AgentSpeechOptionMatcher.swift — isolated spoken-option matching
//

import Foundation

/// 將語音辨識結果限制在題目既有的 option label 內。
public enum AgentSpeechOptionMatcher {
    /// 先 exact，再接受唯一的 contained match；零個或多個候選一律不自動選取。
    /// 若為二元允許／拒絕標籤，再嘗試口語同義詞（回傳原始 label）。
    /// 合法二元極性 pair 若同一句同時含正負證據（含原始 label 與反向口語別名），在 exact／contained／alias 前回 nil。
    public static func match(transcript: String, labels: [String]) -> String? {
        guard isValid(labels: labels) else { return nil }

        let normalizedTranscript = normalized(transcript)
        guard !normalizedTranscript.isEmpty else { return nil }

        // 二元極性：正反意圖並存時不得自動匹配（含「accept no」「允許不要」等 label+反向別名）。
        if let pair = binaryPolarityPair(labels: labels),
           hasConflictingPolarityEvidence(
               normalizedTranscript: normalizedTranscript,
               pair: pair)
        {
            return nil
        }

        let exact = labels.filter { normalized($0) == normalizedTranscript }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 { return nil }

        // Contained: transcript 須包含完整 option label；禁止 label 反向包含不完整 transcript。
        // 單字元 label 僅 exact match（上方已處理），不做 contained match。
        let contained = labels.filter { label in
            let candidate = normalized(label)
            guard candidate.count > 1 else { return false }
            return normalizedTranscript.contains(candidate)
        }
        if contained.count == 1 { return contained[0] }
        if contained.count > 1 { return nil }

        return matchPolarityAlias(normalizedTranscript: normalizedTranscript, labels: labels)
    }

    /// 辨識請求用的 contextual strings：合法二元極性對才附加隱藏中英別名，否則僅 labels。
    /// UI 顯示的 option label 不受影響。
    public static func contextualStrings(for labels: [String]) -> [String] {
        guard isValid(labels: labels),
              binaryPolarityPair(labels: labels) != nil
        else {
            return labels
        }

        var seen = Set(labels.map(normalized))
        var result = labels
        for alias in Self.spokenPositiveAliases + Self.spokenNegativeAliases {
            let key = normalized(alias)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(alias)
        }
        return result
    }

    /// Parser 與 recognizer 共用的合法 label 判準；辨識前先拒絕正規化後重複的 label。
    public static func isValid(labels: [String]) -> Bool {
        guard !labels.isEmpty else { return false }
        let normalizedLabels = labels.map(normalized)
        guard normalizedLabels.allSatisfy({ !$0.isEmpty }) else { return false }
        return Set(normalizedLabels).count == normalizedLabels.count
    }

    /// 語音語系判定。
    ///
    /// 未傳偏好時保留既有三參數呼叫的內容判定，供 TTS 使用；帶偏好時依選項
    /// 文字決定純中文／純英文，只有中英混合才採用合法的偏好語系。
    public static func languageCode(
        question: String,
        header: String,
        labels: [String],
        preferredLanguageCode: String? = nil) -> String
    {
        guard let preferredLanguageCode else {
            let text = ([question, header] + labels).joined(separator: " ")
            return containsChinese(in: text) ? "zh-TW" : "en-US"
        }

        switch labelLanguage(labels) {
        case .chinese:
            return "zh-TW"
        case .english:
            return "en-US"
        case .mixed:
            return validPreferredLanguageCode(preferredLanguageCode)
                ?? fallbackLanguageCode(question: question, header: header)
        case .unknown:
            return validPreferredLanguageCode(preferredLanguageCode)
                ?? fallbackLanguageCode(question: question, header: header)
        }
    }

    /// 正規化大小寫、空白、標點與變音符號；保留中文與英文文字本身。
    public static func normalized(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
        let withoutPunctuation = folded.unicodeScalars.map { scalar -> Character? in
            if CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
            {
                return nil
            }
            return Character(String(scalar))
        }.compactMap { $0 }
        return String(withoutPunctuation)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    // MARK: - Binary polarity aliases

    /// Canonical positive option labels (normalized form of each entry).
    private static let canonicalPositiveLabels: [String] = [
        "允許", "接受", "同意", "accept", "allow", "approve", "yes",
    ]

    /// Canonical negative option labels (normalized form of each entry).
    private static let canonicalNegativeLabels: [String] = [
        "拒絕", "不允許", "deny", "reject", "decline", "no",
    ]

    /// Spoken positive aliases (display form; matching uses normalized).
    private static let spokenPositiveAliases: [String] = [
        "go", "yes", "yeah", "do it", "ok", "okay", "sure",
        "可以", "好的", "同意", "執行", "做吧", "允許",
    ]

    /// Spoken negative aliases (display form; matching uses normalized).
    private static let spokenNegativeAliases: [String] = [
        "no", "nope", "dont", "don't", "do not", "stop", "cancel",
        "不要", "不行", "不可以", "拒絕", "取消", "停止",
    ]

    /// 僅當 labels 恰為二元且正規化後唯一對應一正一負 canonical label 時啟用。
    private static func binaryPolarityPair(labels: [String]) -> (positive: String, negative: String)? {
        guard labels.count == 2 else { return nil }

        let positiveSet = Set(canonicalPositiveLabels.map(normalized))
        let negativeSet = Set(canonicalNegativeLabels.map(normalized))

        var positiveOriginal: String?
        var negativeOriginal: String?

        for label in labels {
            let key = normalized(label)
            let isPositive = positiveSet.contains(key)
            let isNegative = negativeSet.contains(key)
            if isPositive && isNegative { return nil }
            if isPositive {
                if positiveOriginal != nil { return nil }
                positiveOriginal = label
            } else if isNegative {
                if negativeOriginal != nil { return nil }
                negativeOriginal = label
            } else {
                return nil
            }
        }

        guard let positiveOriginal, let negativeOriginal else { return nil }
        return (positiveOriginal, negativeOriginal)
    }

    private static func matchPolarityAlias(
        normalizedTranscript: String,
        labels: [String]) -> String?
    {
        guard let pair = binaryPolarityPair(labels: labels) else { return nil }

        let positiveHit = transcriptMatches(
            normalizedTranscript: normalizedTranscript,
            aliases: spokenPositiveAliases)
        let negativeHit = transcriptMatches(
            normalizedTranscript: normalizedTranscript,
            aliases: spokenNegativeAliases)

        switch (positiveHit, negativeHit) {
        case (true, false):
            return pair.positive
        case (false, true):
            return pair.negative
        default:
            // 雙極性、皆無、或不唯一 → nil
            return nil
        }
    }

    /// 正負證據同時出現：原始 pair label 與口語別名皆計入，規則與別名比對一致（英文 token 邊界、中文長片語遮罩）。
    private static func hasConflictingPolarityEvidence(
        normalizedTranscript: String,
        pair: (positive: String, negative: String)) -> Bool
    {
        let positiveEvidence = spokenPositiveAliases + [pair.positive]
        let negativeEvidence = spokenNegativeAliases + [pair.negative]
        let positiveHit = transcriptMatches(
            normalizedTranscript: normalizedTranscript,
            aliases: positiveEvidence)
        let negativeHit = transcriptMatches(
            normalizedTranscript: normalizedTranscript,
            aliases: negativeEvidence)
        return positiveHit && negativeHit
    }

    /// 合併中英別名比對：英文需 token／片語邊界；中文用完整安全片語並以長度優先避免「不可以」誤觸「可以」。
    private static func transcriptMatches(
        normalizedTranscript: String,
        aliases: [String]) -> Bool
    {
        // 以長度優先掃過所有別名，命中後從剩餘文字剔除該片語，避免子字串二次命中。
        // 正負極性各自呼叫此函式時使用完整 transcript 副本；「不可以」vs「可以」在各自集合內由長度處理。
        // 跨極性時：若 transcript 同時含正負別名，兩邊皆 true，上層回 nil。
        // 但「不可以」含「可以」時，正極性集合只有「可以」會誤中——需在正極性比對時排除已被負向較長片語覆蓋的情況。

        let normalizedAliases = aliases
            .map(normalized)
            .filter { !$0.isEmpty }

        // 先處理中文片語（無空白者視為 CJK 片語）與英文片語分開
        let chinese = normalizedAliases.filter { !$0.contains(" ") && containsChinese(in: $0) }
        let english = normalizedAliases.filter { !chinese.contains($0) }

        if matchesEnglishAliases(normalizedTranscript: normalizedTranscript, aliases: english) {
            return true
        }
        if matchesChineseAliases(normalizedTranscript: normalizedTranscript, aliases: chinese) {
            return true
        }
        return false
    }

    private static func matchesEnglishAliases(
        normalizedTranscript: String,
        aliases: [String]) -> Bool
    {
        for alias in aliases {
            if englishPhraseMatches(normalizedTranscript: normalizedTranscript, phrase: alias) {
                return true
            }
        }
        return false
    }

    /// Whole token / phrase boundaries for English aliases.
    private static func englishPhraseMatches(
        normalizedTranscript: String,
        phrase: String) -> Bool
    {
        guard !phrase.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        // (^|\\s) phrase ($|\\s) — 片語邊界，避免 "now" 命中 "no"、"going" 命中 "go"
        let pattern = "(?:^|\\s)\(escaped)(?:$|\\s)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(normalizedTranscript.startIndex..., in: normalizedTranscript)
        return regex.firstMatch(in: normalizedTranscript, options: [], range: range) != nil
    }

    /// 中文完整安全片語；以更長口語片語遮罩後再測，避免「不可以」誤判為「可以」。
    private static func matchesChineseAliases(
        normalizedTranscript: String,
        aliases: [String]) -> Bool
    {
        let sorted = aliases.sorted { $0.count > $1.count }
        for alias in sorted {
            guard alias.count >= 2 else { continue } // 禁單字元別名

            // 若存在更長的口語片語（任一極性）包含此 alias，先從副本剔除再測。
            let longerBlockers = allChineseSpokenAliases.filter { other in
                other.count > alias.count && other.contains(alias)
            }
            var scratch = normalizedTranscript
            for blocker in longerBlockers.sorted(by: { $0.count > $1.count }) {
                scratch = scratch.replacingOccurrences(
                    of: blocker,
                    with: String(repeating: " ", count: blocker.count))
            }

            if scratch.contains(alias) {
                return true
            }
        }
        return false
    }

    private static var allChineseSpokenAliases: [String] {
        (spokenPositiveAliases + spokenNegativeAliases)
            .map(normalized)
            .filter { !$0.isEmpty && !$0.contains(" ") && containsChinese(in: $0) }
    }

    // MARK: - Language helpers

    private static func containsChinese(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x3100...0x312F).contains(scalar.value)
                || (0x31A0...0x31BF).contains(scalar.value)
        }
    }

    private enum LabelLanguage {
        case chinese
        case english
        case mixed
        case unknown
    }

    private static func labelLanguage(_ labels: [String]) -> LabelLanguage {
        let text = labels.joined(separator: " ")
        let hasChinese = containsChinese(in: text)
        let hasEnglish = containsEnglish(in: text)
        switch (hasChinese, hasEnglish) {
        case (true, true): return .mixed
        case (true, false): return .chinese
        case (false, true): return .english
        case (false, false): return .unknown
        }
    }

    private static func containsEnglish(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x0041...0x005A).contains(scalar.value)
                || (0x0061...0x007A).contains(scalar.value)
        }
    }

    private static func validPreferredLanguageCode(_ value: String) -> String? {
        switch value {
        case "zh-TW", "en-US": return value
        default: return nil
        }
    }

    private static func fallbackLanguageCode(question: String, header: String) -> String {
        containsChinese(in: "\(question) \(header)") ? "zh-TW" : "en-US"
    }
}
