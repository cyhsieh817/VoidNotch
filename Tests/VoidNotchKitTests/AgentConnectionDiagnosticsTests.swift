import XCTest
@testable import VoidNotchKit

private struct FakeFS: FileSystemReading {
    var files: [String: Data]
    func fileExists(_ url: URL) -> Bool { files[url.path] != nil }
    func readData(_ url: URL) -> Data? { files[url.path] }
}

final class HermesHookAdapterTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func paths() -> HookPaths {
        HookPaths(
            home: home,
            appSupportHooks: home.appendingPathComponent("Library/Application Support/VoidNotch/hooks"),
            bundledRelay: URL(fileURLWithPath: "/bundle/relay.sh"),
            bundledPiExtension: URL(fileURLWithPath: "/bundle/voidnotch.ts")
        )
    }

    private func fs(config: String?, allowlist: String?) -> FakeFS {
        var files: [String: Data] = [home.appendingPathComponent(".hermes").path: Data()]
        if let config {
            files[paths().hermesConfig.path] = Data(config.utf8)
        }
        if let allowlist {
            files[paths().hermesAllowlist.path] = Data(allowlist.utf8)
        }
        return FakeFS(files: files)
    }

    private let wiredConfig = """
    hooks:
      on_session_start:
        - command: bash "/x/relay.sh" --provider hermes
    """
    private let approvedAllowlist = """
    {"approvals":[{"event":"on_session_start","command":"bash \\"/x/relay.sh\\" --provider hermes"}]}
    """

    func test_agentAbsent_when_hermes_not_installed() {
        let adapter = HermesHookAdapter(fs: FakeFS(files: [:]))
        XCTAssertEqual(adapter.detect(fs: FakeFS(files: [:]), paths: paths()), .agentAbsent)
    }

    func test_notInstalled_when_config_lacks_relay() {
        let f = fs(config: "hooks: {}\n", allowlist: nil)
        XCTAssertEqual(HermesHookAdapter(fs: f).detect(fs: f, paths: paths()), .notInstalled)
    }

    /// 這是最會騙人的狀態：config.yaml 掛好了，看起來已接通，
    /// 但 hooks_auto_accept:false 下未進 allowlist 的 hook 會被**靜默略過**。
    /// 只看 config 就判 installed，面板會謊報「已接通」而使用者永遠等不到通知。
    func test_conflict_when_configured_but_not_allowlisted() {
        let f = fs(config: wiredConfig, allowlist: nil)
        guard case .conflict(let reason) = HermesHookAdapter(fs: f).detect(fs: f, paths: paths()) else {
            return XCTFail("設定在但未 allowlist，必須報 conflict，不可判為 installed")
        }
        XCTAssertTrue(reason.contains("allowlist"), "理由要講清楚是 allowlist 的問題：\(reason)")
    }

    func test_conflict_when_allowlist_exists_but_lacks_our_command() {
        let f = fs(config: wiredConfig, allowlist: #"{"approvals":[]}"#)
        guard case .conflict = HermesHookAdapter(fs: f).detect(fs: f, paths: paths()) else {
            return XCTFail("allowlist 沒有我們的命令，等同未核准")
        }
    }

    func test_installed_when_configured_and_allowlisted() {
        let f = fs(config: wiredConfig, allowlist: approvedAllowlist)
        XCTAssertEqual(HermesHookAdapter(fs: f).detect(fs: f, paths: paths()), .installed)
    }

    /// hermes 不能一鍵接通。空 plan 會讓 installAll 回報 success，等於謊報接通。
    func test_plan_throws_instead_of_silently_succeeding() {
        let f = fs(config: nil, allowlist: nil)
        XCTAssertThrowsError(try HermesHookAdapter(fs: f).plan(paths: paths()))
    }
}

final class AgentConnectionDiagnosticsTests: XCTestCase {
    func test_absent_agents_are_hidden_from_the_panel() {
        let states = AgentConnectionDiagnostics.states(from: [
            .claude: .installed,
            .codex: .agentAbsent,
            .hermes: .conflict("未列入 allowlist"),
        ])
        XCTAssertEqual(states.map(\.provider), [.claude, .hermes], "沒裝的 agent 不該佔版面")
    }

    func test_conflict_counts_as_needing_attention() {
        let states = AgentConnectionDiagnostics.states(from: [
            .claude: .installed,
            .codex: .notInstalled,
            .hermes: .conflict("未列入 allowlist"),
        ])
        // conflict 不是「已接通」——設定在、卻不會跑
        XCTAssertEqual(AgentConnectionDiagnostics.attentionCount(states), 2)
        XCTAssertFalse(states.first { $0.provider == .hermes }!.isWired)
    }

    func test_detail_tells_you_what_to_do_next() {
        let l10n = L10n(.zhTW)
        let notWired = AgentConnectionState(provider: .codex, hook: .notInstalled)
        XCTAssertTrue(notWired.detail(l10n).contains("接通"))

        let hermes = AgentConnectionState(provider: .hermes, hook: .installed)
        XCTAssertTrue(hermes.detail(l10n).contains("只顯示活動"), "要講明 hermes 不是壞了，是協定做不到")
    }

    func test_detail_is_english_in_en_locale() {
        let l10n = L10n(.en)
        let notWired = AgentConnectionState(provider: .codex, hook: .notInstalled)
        XCTAssertFalse(notWired.detail(l10n).contains(where: { $0.isChineseCharacter }))

        let hermes = AgentConnectionState(provider: .hermes, hook: .installed)
        XCTAssertFalse(hermes.detail(l10n).contains(where: { $0.isChineseCharacter }))

        let conflict = AgentConnectionState(provider: .grok, hook: .conflict("not in allowlist"))
        XCTAssertFalse(conflict.detail(l10n).contains(where: { $0.isChineseCharacter }))
    }
}

private extension Character {
    /// CJK Unified Ideographs block — good enough to catch stray hardcoded Chinese in EN strings.
    var isChineseCharacter: Bool {
        unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}
