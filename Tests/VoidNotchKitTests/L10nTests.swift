import XCTest
@testable import VoidNotchKit

final class L10nTests: XCTestCase {
    func test_english_strings() {
        let l10n = L10n(.en)
        XCTAssertEqual(l10n.menuSettings, "VoidNotch Settings...")
        XCTAssertEqual(l10n.tabSystem, "System")
        XCTAssertEqual(l10n.modelUsageTitle, "Model Usage")
        XCTAssertEqual(l10n.agentActivityTitle, "Agent Activity")
        XCTAssertEqual(l10n.pillActive, "Active")
        XCTAssertEqual(l10n.leftPercent(42), "Left 42%")
        XCTAssertEqual(l10n.usedPercent(7), "Used 7%")
        XCTAssertEqual(l10n.language, .en)
    }

    func test_zhTW_strings() {
        let l10n = L10n(.zhTW)
        XCTAssertEqual(l10n.menuSettings, "VoidNotch 設定…")
        XCTAssertEqual(l10n.tabSystem, "系統監控")
        XCTAssertEqual(l10n.modelUsageTitle, "模型用量")
        XCTAssertEqual(l10n.agentActivityTitle, "Agent 活動")
        XCTAssertEqual(l10n.pillActive, "進行中")
        XCTAssertEqual(l10n.leftPercent(42), "剩 42%")
        XCTAssertEqual(l10n.usedPercent(7), "已用 7%")
        XCTAssertEqual(l10n.language, .zhTW)
    }

    func test_rawValue_init_resolves_language() {
        XCTAssertEqual(L10n(rawValue: "en").menuQuit, "Quit VoidNotch")
        XCTAssertEqual(L10n(rawValue: "zh-TW").menuQuit, "結束 VoidNotch")
        // unknown falls back to AppLanguage.default (.en)
        XCTAssertEqual(L10n(rawValue: "ja").menuQuit, "Quit VoidNotch")
    }

    func test_shared_keys_are_language_invariant() {
        XCTAssertEqual(L10n(.en).cpu, "CPU")
        XCTAssertEqual(L10n(.zhTW).cpu, "CPU")
        XCTAssertEqual(L10n(.en).disk, "Disk")
        XCTAssertEqual(L10n(.zhTW).disk, "Disk")
    }

    /// 新增 L10n key 的 EN 字串不得含 CJK（英文介面回歸鎖）。
    func test_new_l10n_keys_english_have_no_cjk() {
        let l10n = L10n(.en)
        let samples: [String] = [
            l10n.gaugeMenuItems,
            l10n.gaugeClickThrough,
            l10n.gaugeLockPosition,
            l10n.gaugeHide,
            l10n.menuToggleGauge,
            l10n.menubarModeOff,
            l10n.menubarModeIcon,
            l10n.menubarModeMetrics,
            l10n.menubarModeTitle,
            l10n.menubarModeHint,
            l10n.hookWiringTitle,
            l10n.hookWire,
            l10n.hookUnwire,
            l10n.hookStatusInstalled,
            l10n.hookStatusNotInstalled,
            l10n.hookStatusAgentAbsent,
            l10n.hookStatusConflict("path clash"),
            l10n.hookUnwireComingSoon,
            l10n.hookVerifyFailed,
            l10n.hookPromptBanner(3),
            l10n.enable,
            l10n.later,
            l10n.hookInstalledSuffix,
            l10n.hookInstallFailedFallback,
        ]
        for sample in samples {
            XCTAssertFalse(
                sample.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                "EN string must not contain CJK: \(sample)")
        }
    }

    func test_systemMetricKind_label_localized() {
        XCTAssertEqual(SystemMetricKind.cpu.label(language: .zhTW), "CPU")
        XCTAssertEqual(SystemMetricKind.cpu.label(language: .en), "CPU")
        XCTAssertEqual(SystemMetricKind.gpu.label(language: .zhTW), "GPU")
        XCTAssertEqual(SystemMetricKind.gpu.label(language: .en), "GPU")

        XCTAssertEqual(SystemMetricKind.memory.label(language: .zhTW), "記憶體")
        XCTAssertEqual(SystemMetricKind.memory.label(language: .en), "Memory")
        XCTAssertEqual(SystemMetricKind.disk.label(language: .zhTW), "磁碟")
        XCTAssertEqual(SystemMetricKind.disk.label(language: .en), "Disk")
        XCTAssertEqual(SystemMetricKind.network.label(language: .zhTW), "網路")
        XCTAssertEqual(SystemMetricKind.network.label(language: .en), "Network")
        XCTAssertEqual(SystemMetricKind.battery.label(language: .zhTW), "電池")
        XCTAssertEqual(SystemMetricKind.battery.label(language: .en), "Battery")
        XCTAssertEqual(SystemMetricKind.temperature.label(language: .zhTW), "溫度")
        XCTAssertEqual(SystemMetricKind.temperature.label(language: .en), "Temp")
        XCTAssertEqual(SystemMetricKind.health.label(language: .zhTW), "健康度")
        XCTAssertEqual(SystemMetricKind.health.label(language: .en), "Health")
        XCTAssertEqual(SystemMetricKind.host.label(language: .zhTW), "主機")
        XCTAssertEqual(SystemMetricKind.host.label(language: .en), "Host")
        XCTAssertEqual(SystemMetricKind.processes.label(language: .zhTW), "行程")
        XCTAssertEqual(SystemMetricKind.processes.label(language: .en), "Processes")
    }

    /// 語音 L10n：中英皆非空；英文不得含 CJK。
    func test_agentSpeech_l10n_strings_non_empty() {
        let en = L10n(.en)
        let zh = L10n(.zhTW)
        let enSamples: [String] = [
            en.alertsTabSpeech,
            en.agentSpeechTitle,
            en.agentSpeechEnabled,
            en.agentSpeechHint,
            en.agentSpeechChineseVoice,
            en.agentSpeechEnglishVoice,
            en.agentSpeechRate,
            en.agentSpeechSystemVoice,
            en.agentSpeechPreview,
            en.agentSpeechNeedsInput,
            en.agentSpeechFailed,
            en.agentSpeechResourceLimit,
            en.agentInputTerminalHint,
            en.agentSpeechMicrophone,
            en.agentSpeechListening,
            en.agentSpeechNoMatch,
            en.agentSpeechUnavailable,
            en.agentSpeechPermissionDenied,
        ]
        let zhSamples: [String] = [
            zh.alertsTabSpeech,
            zh.agentSpeechTitle,
            zh.agentSpeechEnabled,
            zh.agentSpeechHint,
            zh.agentSpeechChineseVoice,
            zh.agentSpeechEnglishVoice,
            zh.agentSpeechRate,
            zh.agentSpeechSystemVoice,
            zh.agentSpeechPreview,
            zh.agentSpeechNeedsInput,
            zh.agentSpeechFailed,
            zh.agentSpeechResourceLimit,
            zh.agentInputTerminalHint,
            zh.agentSpeechMicrophone,
            zh.agentSpeechListening,
            zh.agentSpeechNoMatch,
            zh.agentSpeechUnavailable,
            zh.agentSpeechPermissionDenied,
        ]
        for sample in enSamples {
            XCTAssertFalse(sample.isEmpty, "EN speech L10n must be non-empty")
            XCTAssertFalse(
                sample.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                "EN speech string must not contain CJK: \(sample)")
        }
        for sample in zhSamples {
            XCTAssertFalse(sample.isEmpty, "zh-TW speech L10n must be non-empty")
        }
    }
}
