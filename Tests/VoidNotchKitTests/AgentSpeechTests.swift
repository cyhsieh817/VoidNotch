import Foundation
import XCTest
@testable import VoidNotchKit

final class AgentSpeechTests: XCTestCase {

    // MARK: - completion gating

    func test_nonCompleted_returnsNil() {
        let statuses: [AgentActivityStatus] = [
            .started, .running, .needsInput, .failed, .resourceLimit, .stopped,
        ]
        for status in statuses {
            let event = AgentActivityEvent(
                provider: .codex,
                status: status,
                title: "do something")
            XCTAssertNil(
                AgentSpeechMessage.completion(for: event),
                "status \(status) must not produce speech")
        }
    }

    private func request(
        question: String = "Choose a mode",
        header: String = "Mode",
        labels: [String] = ["Fast", "Safe"],
        multiSelect: Bool = false
    ) -> AgentInputRequest {
        AgentInputRequest(
            requestID: UUID(),
            questions: [AgentInputQuestion(
                question: question,
                header: header,
                options: labels.map { AgentInputOption(label: $0, description: "") },
                multiSelect: multiSelect)])
    }

    func test_event_based_messages_cover_needsInput_failed_and_resourceLimit() throws {
        let input = request()
        let needsInput = AgentActivityEvent(
            provider: .codex,
            status: .needsInput,
            title: "needs input",
            inputRequest: input)
        let failed = AgentActivityEvent(provider: .claude, status: .failed, title: "Build failed")
        let limited = AgentActivityEvent(provider: .pi, status: .resourceLimit, title: "Context limit")

        let inputMessage = try XCTUnwrap(AgentSpeechMessage.event(for: needsInput))
        XCTAssertEqual(inputMessage.language, .enUS)
        XCTAssertTrue(inputMessage.text.contains("Choose a mode"))
        XCTAssertTrue(inputMessage.text.contains("Fast"))
        XCTAssertTrue(inputMessage.text.count <= AgentSpeechMessage.maximumTextLength)
        XCTAssertTrue(AgentSpeechMessage.event(for: failed)?.text.contains("failed") == true)
        XCTAssertTrue(AgentSpeechMessage.event(for: limited)?.text.contains("resource limit") == true)
    }

    func test_needsInput_speech_detects_chinese_from_question_and_options() throws {
        let event = AgentActivityEvent(
            provider: .pi,
            status: .needsInput,
            title: "需要選擇",
            inputRequest: request(question: "選擇執行模式", header: "模式", labels: ["快速", "安全"]))
        let message = try XCTUnwrap(AgentSpeechMessage.event(for: event))
        XCTAssertEqual(message.language, .zhTW)
        XCTAssertTrue(message.text.contains("快速"))
    }

    func test_plain_needsInput_says_return_to_terminal() throws {
        let event = AgentActivityEvent(provider: .codex, status: .needsInput, title: "Permission")
        let message = try XCTUnwrap(AgentSpeechMessage.event(for: event))
        XCTAssertTrue(message.text.localizedCaseInsensitiveContains("terminal"))
    }

    func test_matcher_exact_contained_ambiguous_and_invalid() {
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "  CAFE! ", labels: ["Café", "Tea"]), "Café")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "please choose tea now", labels: ["Café", "Tea"]), "Tea")
        // 英文字首不得因反向 contains 過早選取完整選項
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "t", labels: ["Café", "Tea"]))
        // 中文單字元僅 exact match
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "是", labels: ["是", "否"]), "是")
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "red and green", labels: ["Red", "Green"]))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "unknown", labels: ["Red", "Green"]))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "yes", labels: ["Yes", " yes "]))
        XCTAssertFalse(AgentSpeechOptionMatcher.isValid(labels: ["Yes", " yes "]))
    }

    // MARK: - binary polarity spoken aliases

    func test_matcher_binary_allow_reject_english_spoken_aliases() {
        let labels = ["Allow", "Reject"]
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "go", labels: labels), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "yes", labels: labels), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "yeah", labels: labels), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "do it", labels: labels), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "ok", labels: labels), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "okay", labels: labels), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "sure", labels: labels), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "no", labels: labels), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "nope", labels: labels), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "dont", labels: labels), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "don't", labels: labels), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "do not", labels: labels), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "stop", labels: labels), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "cancel", labels: labels), "Reject")
    }

    func test_matcher_binary_accept_reject_english_spoken_aliases() {
        let labels = ["Accept", "Reject"]
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "go", labels: labels), "Accept")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "yes", labels: labels), "Accept")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "yeah", labels: labels), "Accept")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "do it", labels: labels), "Accept")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "no", labels: labels), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "nope", labels: labels), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "dont", labels: labels), "Reject")
    }

    func test_matcher_binary_allow_reject_chinese_spoken_aliases() {
        let labels = ["允許", "拒絕"]
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "可以", labels: labels), "允許")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "好的", labels: labels), "允許")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "同意", labels: labels), "允許")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "執行", labels: labels), "允許")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "做吧", labels: labels), "允許")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "允許", labels: labels), "允許")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "不要", labels: labels), "拒絕")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "不行", labels: labels), "拒絕")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "拒絕", labels: labels), "拒絕")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "取消", labels: labels), "拒絕")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "停止", labels: labels), "拒絕")
        // 「不可以」不得因包含「可以」而落正
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "不可以", labels: labels), "拒絕")
    }

    func test_matcher_binary_mixed_spoken_aliases_across_languages() {
        let allowReject = ["Allow", "Reject"]
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "可以", labels: allowReject), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "不要", labels: allowReject), "Reject")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "go", labels: ["允許", "拒絕"]), "允許")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "nope", labels: ["允許", "拒絕"]), "拒絕")

        let acceptReject = ["Accept", "Reject"]
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "好的", labels: acceptReject), "Accept")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "取消", labels: acceptReject), "Reject")
    }

    func test_matcher_binary_both_polarities_returns_nil() {
        let labels = ["Allow", "Reject"]
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "yes no", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "可以 不要", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "go stop", labels: labels))

        // 原始 label + 反向口語別名：exact/contained 前亦須拒絕
        let acceptReject = ["Accept", "Reject"]
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "accept no", labels: acceptReject))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "reject yes", labels: acceptReject))

        let allowRejectZH = ["允許", "拒絕"]
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "允許不要", labels: allowRejectZH))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "拒絕可以", labels: allowRejectZH))
    }

    func test_matcher_alias_mode_requires_unique_binary_polarity_pair() {
        // 三選項不啟用別名
        XCTAssertNil(AgentSpeechOptionMatcher.match(
            transcript: "yes",
            labels: ["Allow", "Reject", "Skip"]))
        // 無關二元選項不啟用別名
        XCTAssertNil(AgentSpeechOptionMatcher.match(
            transcript: "yes",
            labels: ["Fast", "Safe"]))
        XCTAssertNil(AgentSpeechOptionMatcher.match(
            transcript: "go",
            labels: ["Red", "Green"]))
        // 雙正或雙負不啟用
        XCTAssertNil(AgentSpeechOptionMatcher.match(
            transcript: "yes",
            labels: ["Allow", "Accept"]))
        XCTAssertNil(AgentSpeechOptionMatcher.match(
            transcript: "no",
            labels: ["Reject", "Deny"]))
    }

    func test_matcher_english_aliases_require_token_boundaries() {
        let labels = ["Allow", "Reject"]
        // "now" 不得命中 "no"；"going" 不得命中 "go"
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "now", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "going", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "notable", labels: labels))
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "please say yes now", labels: labels), "Allow")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "I said no thanks", labels: labels), "Reject")
    }

    func test_contextualStrings_include_aliases_for_binary_polarity_only() {
        let allowReject = ["Allow", "Reject"]
        let contextual = AgentSpeechOptionMatcher.contextualStrings(for: allowReject)
        // 原始 labels 置於前端且不變
        XCTAssertEqual(Array(contextual.prefix(2)), allowReject)
        XCTAssertTrue(contextual.contains("go"))
        XCTAssertTrue(contextual.contains("yes"))
        XCTAssertTrue(contextual.contains("yeah"))
        XCTAssertTrue(contextual.contains("do it"))
        XCTAssertTrue(contextual.contains("no"))
        XCTAssertTrue(contextual.contains("nope"))
        XCTAssertTrue(contextual.contains("可以"))
        XCTAssertTrue(contextual.contains("不可以"))
        XCTAssertTrue(contextual.contains("不要"))

        // 非二元極性：labels 置前、不帶極性別名（labels > 1 時會另附序號別名）
        let unrelated = ["Fast", "Safe"]
        let unrelatedContextual = AgentSpeechOptionMatcher.contextualStrings(for: unrelated)
        XCTAssertEqual(Array(unrelatedContextual.prefix(2)), unrelated)
        XCTAssertFalse(unrelatedContextual.contains("yes"))
        XCTAssertFalse(unrelatedContextual.contains("不要"))

        let three = ["Allow", "Reject", "Skip"]
        let threeContextual = AgentSpeechOptionMatcher.contextualStrings(for: three)
        XCTAssertEqual(Array(threeContextual.prefix(3)), three)
        XCTAssertFalse(threeContextual.contains("yes"))

        // UI labels 本身不因 helper 改變
        XCTAssertEqual(allowReject, ["Allow", "Reject"])
    }

    func test_matcher_still_prefers_exact_and_contained_over_aliases() {
        // exact 優先
        XCTAssertEqual(
            AgentSpeechOptionMatcher.match(transcript: "Allow", labels: ["Allow", "Reject"]),
            "Allow")
        // contained 優先於別名
        XCTAssertEqual(
            AgentSpeechOptionMatcher.match(transcript: "please Reject this", labels: ["Allow", "Reject"]),
            "Reject")
    }

    // MARK: - ordinal selection (序號選答)

    func test_matcher_chinese_ordinal_hits() {
        let labels = ["快速", "安全", "詳細"]
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "第一個", labels: labels), "快速")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "第二", labels: labels), "安全")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "三", labels: labels), "詳細")
    }

    func test_matcher_english_ordinal_hits() {
        let labels = ["Fast", "Safe", "Detailed"]
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "first", labels: labels), "Fast")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "option 2", labels: labels), "Safe")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "number 3", labels: labels), "Detailed")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "2", labels: labels), "Safe")
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "third", labels: labels), "Detailed")
    }

    func test_matcher_ordinal_out_of_range_returns_nil() {
        let labels = ["Fast", "Safe"]
        // 第三個超界
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "第三個", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "third", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "option 3", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "9", labels: labels))
    }

    func test_matcher_ordinal_disabled_when_label_is_digit_or_ordinal_token() {
        // label 含純數字 → 序號路徑停用
        let withDigit = ["1", "Safe", "Fast"]
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "第二個", labels: withDigit))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "second", labels: withDigit))
        // 仍可 exact 命中數字 label
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "1", labels: withDigit), "1")

        // label 本身是序號 token → 停用
        let withOrdinalWord = ["first", "Safe", "Fast"]
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "第二個", labels: withOrdinalWord))
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "first", labels: withOrdinalWord), "first")

        // 僅 1 個 label → 序號路徑停用
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "第一個", labels: ["Only"]))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "1", labels: ["Only"]))
    }

    // MARK: - unique fuzzy match

    func test_matcher_fuzzy_unique_hit() {
        let labels = ["Apple", "Banana"]
        // 單字元差（替換）
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "appla", labels: labels), "Apple")
        // 刪一字
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "aple", labels: labels), "Apple")
        // 增一字
        XCTAssertEqual(AgentSpeechOptionMatcher.match(transcript: "applee", labels: labels), "Apple")
    }

    func test_matcher_fuzzy_multiple_hits_returns_nil() {
        // 兩個 label 皆與 transcript 距離 ≤1
        let labels = ["Alpha", "Alphd"]
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "alphb", labels: labels))
    }

    func test_matcher_binary_polarity_skips_fuzzy() {
        // allow/deny 類不做模糊；即使距離 ≤1 也不命中
        let labels = ["Allow", "Reject"]
        // "allov" 對 Allow 距離 1，長度 ≥4，但二元極性 pair 整組跳過模糊
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "allov", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "rejec", labels: labels))
    }

    func test_matcher_polarity_conflict_still_blocks_before_ordinal_and_fuzzy() {
        // 既有極性衝突案例不回歸：正反並存仍 nil，不落入序號／模糊
        let labels = ["Allow", "Reject"]
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "yes no", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "可以 不要", labels: labels))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "accept no", labels: ["Accept", "Reject"]))
        XCTAssertNil(AgentSpeechOptionMatcher.match(transcript: "允許不要", labels: ["允許", "拒絕"]))
    }

    func test_contextualStrings_append_ordinal_aliases_when_multiple_labels() {
        let labels = ["Fast", "Safe", "Detailed"]
        let contextual = AgentSpeechOptionMatcher.contextualStrings(for: labels)
        // 原始 labels 置前且不變
        XCTAssertEqual(Array(contextual.prefix(3)), labels)
        XCTAssertTrue(contextual.contains("第一個"))
        XCTAssertTrue(contextual.contains("第二個"))
        XCTAssertTrue(contextual.contains("第三個"))
        XCTAssertTrue(contextual.contains("first"))
        XCTAssertTrue(contextual.contains("second"))
        XCTAssertTrue(contextual.contains("third"))
        XCTAssertTrue(contextual.contains("option 1"))
        XCTAssertTrue(contextual.contains("option 2"))
        XCTAssertTrue(contextual.contains("option 3"))
        // UI labels 本身不因 helper 改變
        XCTAssertEqual(labels, ["Fast", "Safe", "Detailed"])

        // 二元極性：極性別名仍在，序號別名一併附加
        let allowReject = ["Allow", "Reject"]
        let binaryContextual = AgentSpeechOptionMatcher.contextualStrings(for: allowReject)
        XCTAssertEqual(Array(binaryContextual.prefix(2)), allowReject)
        XCTAssertTrue(binaryContextual.contains("yes"))
        XCTAssertTrue(binaryContextual.contains("第一個"))
        XCTAssertTrue(binaryContextual.contains("first"))
        XCTAssertTrue(binaryContextual.contains("option 1"))
    }

    func test_languageCode_pureChineseLabels_ignoreEnglishPreference() {
        XCTAssertEqual(
            AgentSpeechOptionMatcher.languageCode(
                question: "Choose a mode",
                header: "Mode",
                labels: ["快速", "安全"],
                preferredLanguageCode: "en-US"),
            "zh-TW")
    }

    func test_languageCode_pureEnglishLabels_ignoreChinesePreference() {
        XCTAssertEqual(
            AgentSpeechOptionMatcher.languageCode(
                question: "選擇模式",
                header: "模式",
                labels: ["Fast", "Safe"],
                preferredLanguageCode: "zh-TW"),
            "en-US")
    }

    func test_languageCode_mixedLabels_followEnglishAndChinesePreferences() {
        let question = "選擇一個模式"
        let header = "模式"
        let labels = ["Fast", "安全"]
        XCTAssertEqual(
            AgentSpeechOptionMatcher.languageCode(
                question: question,
                header: header,
                labels: labels,
                preferredLanguageCode: "en-US"),
            "en-US")
        XCTAssertEqual(
            AgentSpeechOptionMatcher.languageCode(
                question: question,
                header: header,
                labels: labels,
                preferredLanguageCode: "zh-TW"),
            "zh-TW")
    }

    func test_languageCode_mixedLabels_invalidPreference_hasStableContentFallback() {
        let arguments = (
            question: "選擇一個模式",
            header: "模式",
            labels: ["Fast", "安全"])
        let first = AgentSpeechOptionMatcher.languageCode(
            question: arguments.question,
            header: arguments.header,
            labels: arguments.labels,
            preferredLanguageCode: "en")
        let second = AgentSpeechOptionMatcher.languageCode(
            question: arguments.question,
            header: arguments.header,
            labels: arguments.labels,
            preferredLanguageCode: "en")
        XCTAssertEqual(first, "zh-TW")
        XCTAssertEqual(second, first)

        XCTAssertEqual(
            AgentSpeechOptionMatcher.languageCode(
                question: "Choose a mode",
                header: "Mode",
                labels: arguments.labels,
                preferredLanguageCode: "en"),
            "en-US")
    }

    func test_languageCode_threeArgumentCall_keepsTTSContentDetection() {
        XCTAssertEqual(
            AgentSpeechOptionMatcher.languageCode(
                question: "選擇一個模式",
                header: "模式",
                labels: ["Fast", "Safe"]),
            "zh-TW")
    }

    func test_completed_chinese_title() {
        let event = AgentActivityEvent(
            provider: .claude,
            status: .completed,
            title: "修好授權流程")
        let message = AgentSpeechMessage.completion(for: event)
        XCTAssertEqual(message?.language, .zhTW)
        XCTAssertEqual(message?.language.languageCode, "zh-TW")
        XCTAssertEqual(message?.text, "Claude 已完成：修好授權流程")
    }

    func test_completed_english_title() {
        let event = AgentActivityEvent(
            provider: .codex,
            status: .completed,
            title: "Fix license flow")
        let message = AgentSpeechMessage.completion(for: event)
        XCTAssertEqual(message?.language, .enUS)
        XCTAssertEqual(message?.language.languageCode, "en-US")
        XCTAssertEqual(message?.text, "Codex completed: Fix license flow")
    }

    func test_bopomofo_title_is_chinese() {
        let event = AgentActivityEvent(
            provider: .pi,
            status: .completed,
            title: "\u{3100}ㄅㄆㄇ task")
        let message = AgentSpeechMessage.completion(for: event)
        XCTAssertEqual(message?.language, .zhTW)
        XCTAssertEqual(message?.text, "pi 已完成：\u{3100}ㄅㄆㄇ task")
    }

    func test_whitespace_normalization() {
        let event = AgentActivityEvent(
            provider: .grok,
            status: .completed,
            title: "  hello   world\n\tfoo  ")
        let message = AgentSpeechMessage.completion(for: event)
        XCTAssertEqual(message?.text, "Grok completed: hello world foo")
    }

    func test_title_truncated_to_240_characters() throws {
        let long = String(repeating: "a", count: 300)
        let event = AgentActivityEvent(
            provider: .hermes,
            status: .completed,
            title: long)
        let message = try XCTUnwrap(AgentSpeechMessage.completion(for: event))
        let prefix = "Hermes completed: "
        XCTAssertTrue(message.text.hasPrefix(prefix))
        let spokenTitle = String(message.text.dropFirst(prefix.count))
        XCTAssertEqual(spokenTitle.count, 240)
        XCTAssertEqual(spokenTitle, String(repeating: "a", count: 240))
    }

    func test_empty_title_english_fallback() {
        let event = AgentActivityEvent(
            provider: .codex,
            status: .completed,
            title: "   \n\t  ")
        let message = AgentSpeechMessage.completion(for: event)
        XCTAssertEqual(message?.language, .enUS)
        XCTAssertEqual(message?.text, "Codex completed: task")
    }

    func test_detail_and_workspace_not_leaked() throws {
        let secret = "SECRET_TOKEN_XYZ_should_never_speak"
        let workspace = "/Users/private/secret-project"
        let event = AgentActivityEvent(
            provider: .claude,
            status: .completed,
            title: "ship feature",
            detail: secret,
            workspace: workspace)
        let message = try XCTUnwrap(AgentSpeechMessage.completion(for: event))
        XCTAssertEqual(message.text, "Claude completed: ship feature")
        XCTAssertFalse(message.text.contains(secret))
        XCTAssertFalse(message.text.contains(workspace))
        XCTAssertFalse(message.text.contains("private"))
    }

    // MARK: - language codes

    func test_languageCode_values() {
        XCTAssertEqual(AgentSpeechLanguage.zhTW.languageCode, "zh-TW")
        XCTAssertEqual(AgentSpeechLanguage.enUS.languageCode, "en-US")
        XCTAssertEqual(AgentSpeechLanguage.allCases.count, 2)
    }

    // MARK: - preferences

    func test_preferences_defaults() throws {
        let defaults = makeTestDefaults("AgentSpeech.defaults")
        let prefs = AgentSpeechPreferences(userDefaults: defaults)
        XCTAssertFalse(prefs.enabled)
        XCTAssertNil(prefs.chineseVoiceIdentifier)
        XCTAssertNil(prefs.englishVoiceIdentifier)
        XCTAssertEqual(prefs.rate, 0.48, accuracy: 0.0001)
        XCTAssertTrue(prefs.speaksCompleted)
        XCTAssertFalse(prefs.speaksNeedsInput)
        XCTAssertFalse(prefs.speaksFailed)
        XCTAssertFalse(prefs.speaksResourceLimit)
    }

    func test_rate_clamp() throws {
        let defaults = makeTestDefaults("AgentSpeech.rate")
        let prefs = AgentSpeechPreferences(userDefaults: defaults)
        prefs.rate = 0.10
        XCTAssertEqual(prefs.rate, 0.35, accuracy: 0.0001)
        prefs.rate = 0.99
        XCTAssertEqual(prefs.rate, 0.62, accuracy: 0.0001)
        prefs.rate = 0.50
        XCTAssertEqual(prefs.rate, 0.50, accuracy: 0.0001)

        // damaged stored value is clamped on read
        defaults.set(0.01, forKey: AgentSpeechPreferences.Keys.rate)
        XCTAssertEqual(prefs.rate, 0.35, accuracy: 0.0001)
        defaults.set(1.5, forKey: AgentSpeechPreferences.Keys.rate)
        XCTAssertEqual(prefs.rate, 0.62, accuracy: 0.0001)
    }

    func test_nonFinite_rate_usesDefault() throws {
        let defaults = makeTestDefaults("AgentSpeech.nonFiniteRate")
        let prefs = AgentSpeechPreferences(userDefaults: defaults)
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            prefs.rate = value
            XCTAssertEqual(prefs.rate, 0.48, accuracy: 0.0001)
            defaults.set(value, forKey: AgentSpeechPreferences.Keys.rate)
            XCTAssertEqual(prefs.rate, 0.48, accuracy: 0.0001)
        }
    }

    func test_voice_identifier_roundTrip() throws {
        let defaults = makeTestDefaults("AgentSpeech.voice")
        let prefs = AgentSpeechPreferences(userDefaults: defaults)
        prefs.chineseVoiceIdentifier = "com.apple.voice.compact.zh-TW.Meijia"
        prefs.englishVoiceIdentifier = "com.apple.voice.compact.en-US.Samantha"
        XCTAssertEqual(
            prefs.chineseVoiceIdentifier,
            "com.apple.voice.compact.zh-TW.Meijia")
        XCTAssertEqual(
            prefs.englishVoiceIdentifier,
            "com.apple.voice.compact.en-US.Samantha")

        prefs.chineseVoiceIdentifier = nil
        prefs.englishVoiceIdentifier = ""
        XCTAssertNil(prefs.chineseVoiceIdentifier)
        XCTAssertNil(prefs.englishVoiceIdentifier)
        XCTAssertNil(defaults.object(forKey: AgentSpeechPreferences.Keys.chineseVoiceIdentifier))
        XCTAssertNil(defaults.object(forKey: AgentSpeechPreferences.Keys.englishVoiceIdentifier))
    }

    func test_enabled_roundTrip() throws {
        let defaults = makeTestDefaults("AgentSpeech.enabled")
        let prefs = AgentSpeechPreferences(userDefaults: defaults)
        XCTAssertFalse(prefs.enabled)
        prefs.enabled = true
        XCTAssertTrue(prefs.enabled)
        XCTAssertEqual(
            defaults.bool(forKey: AgentSpeechPreferences.Keys.enabled),
            true)
    }

    func test_status_preferences_are_independently_selectable() throws {
        let defaults = makeTestDefaults("AgentSpeech.statuses")
        let prefs = AgentSpeechPreferences(userDefaults: defaults)
        prefs.enabled = true
        XCTAssertTrue(prefs.speaks(.completed))
        XCTAssertFalse(prefs.speaks(.needsInput))
        prefs.speaksNeedsInput = true
        prefs.speaksFailed = true
        prefs.speaksResourceLimit = true
        XCTAssertTrue(prefs.speaks(.needsInput))
        XCTAssertTrue(prefs.speaks(.failed))
        XCTAssertTrue(prefs.speaks(.resourceLimit))
    }

    func test_preference_key_constants() {
        XCTAssertEqual(
            AgentSpeechPreferences.Keys.enabled,
            "VoidNotch.agentSpeech.enabled")
        XCTAssertEqual(
            AgentSpeechPreferences.Keys.chineseVoiceIdentifier,
            "VoidNotch.agentSpeech.chineseVoiceIdentifier")
        XCTAssertEqual(
            AgentSpeechPreferences.Keys.englishVoiceIdentifier,
            "VoidNotch.agentSpeech.englishVoiceIdentifier")
        XCTAssertEqual(
            AgentSpeechPreferences.Keys.rate,
            "VoidNotch.agentSpeech.rate")
    }
}
