import XCTest
@testable import VoidNotchKit

struct StubFS: FileSystemReading {
    var files: [String: Data]
    func fileExists(_ url: URL) -> Bool { files[url.path] != nil }
    func readData(_ url: URL) -> Data? { files[url.path] }
}

final class ProviderKindTests: XCTestCase {
    func test_grokAndPiExistWithNames() {
        XCTAssertEqual(AgentActivityProviderKind(rawValue: "grok"), .grok)
        XCTAssertEqual(AgentActivityProviderKind(rawValue: "pi"), .pi)
        XCTAssertEqual(AgentActivityProviderKind.grok.displayName, "Grok")
        XCTAssertEqual(AgentActivityProviderKind.pi.displayName, "pi")
        XCTAssertEqual(AgentActivityProviderKind.grok.compactName, "Grok")
        XCTAssertEqual(AgentActivityProviderKind.pi.compactName, "pi")
        XCTAssertEqual(AgentActivityProviderKind(rawValue: "hermes"), .hermes)
        XCTAssertEqual(AgentActivityProviderKind.hermes.displayName, "Hermes")
        // 新增 provider 時這裡會紅——提醒你 relay 的 canonical_provider 與
        // AgentActivityWidget 的 icon/tint switch 也要一起補，否則事件會被靜默丟掉。
        XCTAssertEqual(AgentActivityProviderKind.allCases.count, 6)
    }
}

final class HookTypesTests: XCTestCase {
    func test_mutationEquatable() {
        let u = URL(fileURLWithPath: "/tmp/a")
        XCTAssertEqual(HookMutation.backup(u), HookMutation.backup(u))
        XCTAssertEqual(HookStatus.conflict("x"), HookStatus.conflict("x"))
        XCTAssertNotEqual(HookStatus.conflict("x"), HookStatus.installed)
    }
}

final class ClaudeAdapterTests: XCTestCase {
    private func paths(home: URL) -> HookPaths {
        HookPaths(home: home,
                  appSupportHooks: home.appendingPathComponent("AS/hooks"),
                  bundledRelay: URL(fileURLWithPath: "/bundle/relay.sh"),
                  bundledPiExtension: URL(fileURLWithPath: "/bundle/voidnotch.ts"))
    }

    func test_planAddsRelayToFiveEvents() throws {
        let home = URL(fileURLWithPath: "/Users/x")
        let existing = #"{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"/Users/x/.claude/hooks/peon-ping/peon.sh"}]}]}}"#
        let fs = StubFS(files: [home.appendingPathComponent(".claude/settings.json").path: Data(existing.utf8)])
        let adapter = ClaudeHookAdapter(fs: fs)
        let muts = try adapter.plan(paths: paths(home: home))

        // 應有一筆 backup + 一筆 writeJSON
        XCTAssertTrue(muts.contains { if case .backup = $0 { return true }; return false })
        guard case let .writeJSON(_, data)? = muts.first(where: { if case .writeJSON = $0 { return true }; return false }) else {
            return XCTFail("無 writeJSON")
        }
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = obj["hooks"] as! [String: Any]
        for ev in ["SessionStart", "UserPromptSubmit", "Notification", "PermissionRequest", "Stop"] {
            XCTAssertNotNil(hooks[ev], "缺事件 \(ev)")
        }
        // peon.sh 應被移除
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("peon-ping/peon.sh"))
        XCTAssertTrue(json.contains("--voidnotch-relay"))

        guard let preToolUse = hooks["PreToolUse"] as? [[String: Any]],
              let brokerEntry = preToolUse.first(where: { ($0["matcher"] as? String) == "AskUserQuestion" }),
              let brokerHooks = brokerEntry["hooks"] as? [[String: Any]],
              let broker = brokerHooks.first
        else {
            return XCTFail("缺 AskUserQuestion PreToolUse broker")
        }
        XCTAssertEqual(broker["type"] as? String, "command")
        XCTAssertGreaterThanOrEqual(broker["timeout"] as? Int ?? 0, 600)
        XCTAssertTrue((broker["command"] as? String)?.contains("--voidnotch-input-broker") == true)
    }

    func test_detectInstalledWhenMarkerPresent() {
        let home = URL(fileURLWithPath: "/Users/x")
        let already = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash /x/peonping-voidnotch-relay.sh --provider claude --voidnotch-relay --voidnotch-input-broker"}]}]}}"#
        let fs = StubFS(files: [home.appendingPathComponent(".claude/settings.json").path: Data(already.utf8)])
        XCTAssertEqual(ClaudeHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)), .installed)
    }

    func test_detectRequiresInputBrokerMarker() {
        let home = URL(fileURLWithPath: "/Users/x")
        let old = #"{"hooks":{"Stop":[{"hooks":[{"command":"relay --voidnotch-relay"}]}]}}"#
        let fs = StubFS(files: [home.appendingPathComponent(".claude/settings.json").path: Data(old.utf8)])
        XCTAssertEqual(ClaudeHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)), .notInstalled)
    }

    func test_detectAgentAbsentWhenNoDir() {
        let home = URL(fileURLWithPath: "/Users/x")
        let fs = StubFS(files: [:])
        XCTAssertEqual(ClaudeHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)), .agentAbsent)
    }

    func test_planQuotesRelayPathWithSpaces() throws {
        let home = URL(fileURLWithPath: "/Users/x")
        let p = HookPaths(home: home,
                          appSupportHooks: home.appendingPathComponent("Library/Application Support/VoidNotch/hooks"),
                          bundledRelay: URL(fileURLWithPath: "/bundle/relay.sh"),
                          bundledPiExtension: URL(fileURLWithPath: "/bundle/voidnotch.ts"))
        let fs = StubFS(files: [:])
        let muts = try ClaudeHookAdapter(fs: fs).plan(paths: p)
        guard case let .writeJSON(_, data)? = muts.first(where: { if case .writeJSON = $0 { return true }; return false }) else {
            return XCTFail("無 writeJSON")
        }
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("bash \\\"") && json.contains("Application Support"),
                      "relay 路徑應加雙引號")
    }

    func test_detectConflictOnMalformedJSON() {
        let home = URL(fileURLWithPath: "/Users/x")
        let broken = #"{not json"#
        let fs = StubFS(files: [home.appendingPathComponent(".claude/settings.json").path: Data(broken.utf8)])
        XCTAssertEqual(ClaudeHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)), .conflict("settings.json 解析失敗"))
    }
}

final class CodexAdapterTests: XCTestCase {
    private func paths(home: URL) -> HookPaths {
        HookPaths(home: home,
                  appSupportHooks: home.appendingPathComponent("AS/hooks"),
                  bundledRelay: URL(fileURLWithPath: "/bundle/relay.sh"),
                  bundledPiExtension: URL(fileURLWithPath: "/bundle/voidnotch.ts"))
    }

    func test_planPreservesMempalAndAddsRelay() throws {
        let home = URL(fileURLWithPath: "/Users/x")
        let existing = #"{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"mempal cowork-drain --target codex"}]}]}}"#
        let fs = StubFS(files: [home.appendingPathComponent(".codex/hooks.json").path: Data(existing.utf8)])
        let muts = try CodexHookAdapter(fs: fs).plan(paths: paths(home: home))
        guard case let .writeJSON(_, data)? = muts.first(where: { if case .writeJSON = $0 { return true }; return false }) else {
            return XCTFail("無 writeJSON")
        }
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("mempal cowork-drain"))       // 保留
        XCTAssertTrue(json.contains("--provider codex"))
        XCTAssertTrue(json.contains("--voidnotch-relay"))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = obj["hooks"] as! [String: Any]
        XCTAssertNil(hooks["Notification"])                       // Codex 無此事件
        for ev in ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop"] {
            XCTAssertNotNil(hooks[ev], "缺 \(ev)")
        }
    }
}

final class GrokPiAdapterTests: XCTestCase {
    private func paths(home: URL) -> HookPaths {
        HookPaths(home: home,
                  appSupportHooks: home.appendingPathComponent("AS/hooks"),
                  bundledRelay: URL(fileURLWithPath: "/bundle/relay.sh"),
                  bundledPiExtension: URL(fileURLWithPath: "/bundle/voidnotch.ts"))
    }

    func test_grokPlanIsEmpty() throws {
        let home = URL(fileURLWithPath: "/Users/x")
        let fs = StubFS(files: [home.appendingPathComponent(".grok/config.toml").path: Data("[compat.claude]\nhooks = true".utf8)])
        XCTAssertTrue(try GrokHookAdapter(fs: fs).plan(paths: paths(home: home)).isEmpty)
    }

    func test_grokConflictWhenDisabled() {
        let home = URL(fileURLWithPath: "/Users/x")
        let fs = StubFS(files: [home.appendingPathComponent(".grok/config.toml").path: Data("[compat.claude]\nhooks = false".utf8)])
        guard case .conflict = GrokHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)) else {
            return XCTFail("應為 conflict")
        }
    }

    func test_piPlanCopiesExtension() throws {
        let home = URL(fileURLWithPath: "/Users/x")
        let fs = StubFS(files: [home.appendingPathComponent(".pi/agent").path: Data()])
        let muts = try PiHookAdapter(fs: fs).plan(paths: paths(home: home))
        guard case let .copyFile(from, to)? = muts.first(where: { if case .copyFile = $0 { return true }; return false }) else {
            return XCTFail("無 copyFile")
        }
        XCTAssertEqual(from, URL(fileURLWithPath: "/bundle/voidnotch.ts"))
        XCTAssertTrue(to.path.hasSuffix(".pi/agent/extensions/voidnotch.ts"))
    }

    // 舊版擴充（只會發通知、沒有 question 工具）必須被判為 notInstalled 才會被覆蓋升級；
    // 只看「檔案在不在」會讓既有使用者永遠停在舊版。
    func test_piDetectTreatsExtensionWithoutQuestionToolAsNotInstalled() {
        let home = URL(fileURLWithPath: "/Users/x")
        let ext = home.appendingPathComponent(".pi/agent/extensions/voidnotch.ts")
        let fs = StubFS(files: [
            home.appendingPathComponent(".pi/agent").path: Data(),
            ext.path: Data(#"pi.on("session_start", () => {})"#.utf8),
        ])
        XCTAssertEqual(PiHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)), .notInstalled)
    }

    func test_piDetectInstalledWhenQuestionToolMarkerPresent() {
        let home = URL(fileURLWithPath: "/Users/x")
        let ext = home.appendingPathComponent(".pi/agent/extensions/voidnotch.ts")
        let source = #"export const QUESTION_TOOL_MARKER = "voidnotch-question-tool-v1";"#
        let fs = StubFS(files: [
            home.appendingPathComponent(".pi/agent").path: Data(),
            ext.path: Data(source.utf8),
        ])
        XCTAssertEqual(PiHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)), .installed)
    }

    // 回歸：段內 hooks 之前有陣列值不得截斷段掃描（原邏輯遇 `[` 截斷 → 假陰性）
    func test_grokConflictSurvivesArrayBeforeHooks() {
        let home = URL(fileURLWithPath: "/Users/x")
        let toml = "[compat.claude]\nallowed_tools = [\"Bash\", \"Read\"]\nhooks = false"
        let fs = StubFS(files: [home.appendingPathComponent(".grok/config.toml").path: Data(toml.utf8)])
        guard case .conflict = GrokHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)) else {
            return XCTFail("應為 conflict（hooks = false 在陣列值之後仍須偵測到）")
        }
    }

    // 回歸：註解掉的 hooks = false 不得誤判（原裸子字串比對 → 假陽性）
    func test_grokNotConflictOnCommentedHooks() {
        let home = URL(fileURLWithPath: "/Users/x")
        let toml = "[compat.claude]\n# hooks = false\nhooks = true"
        let fs = StubFS(files: [home.appendingPathComponent(".grok/config.toml").path: Data(toml.utf8)])
        if case .conflict = GrokHookAdapter(fs: fs).detect(fs: fs, paths: paths(home: home)) {
            return XCTFail("被註解的 hooks = false 不應觸發 conflict")
        }
    }
}
