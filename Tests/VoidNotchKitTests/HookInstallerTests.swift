import XCTest
@testable import VoidNotchKit

final class HookInstallerTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vnhooktest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func installer(paths: HookPaths) -> HookInstaller {
        HookInstaller(adapters: [], paths: paths, clock: { Date(timeIntervalSince1970: 1000) })
    }

    func test_writeJSONIsAtomicAndBackupsExisting() throws {
        let dir = try tempDir()
        let target = dir.appendingPathComponent("settings.json")
        try Data(#"{"old":1}"#.utf8).write(to: target)
        let inst = installer(paths: HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir))
        try inst.apply([.backup(target), .writeJSON(target, Data(#"{"new":2}"#.utf8))])
        let written = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(written.contains("new"))
        // 備份存在
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains("voidnotch-bak") }
        XCTAssertEqual(backups.count, 1)
    }

    func test_rollbackRestoresBackupOnFailure() throws {
        let dir = try tempDir()
        let good = dir.appendingPathComponent("a.json")
        try Data(#"{"v":1}"#.utf8).write(to: good)
        let badDir = dir.appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let bad = badDir.appendingPathComponent("deep/b.json")  // copyFile 來源不存在 → throw
        let inst = installer(paths: HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir))

        XCTAssertThrowsError(try inst.apply([
            .backup(good),
            .writeJSON(good, Data(#"{"v":2}"#.utf8)),
            .copyFile(from: bad, to: dir.appendingPathComponent("c.json")),  // 這步 throw
        ]))
        // good 應回滾到 v1
        let restored = try String(contentsOf: good, encoding: .utf8)
        XCTAssertTrue(restored.contains("\"v\":1") || restored.contains("\"v\" : 1"))
    }

    func test_rollbackDeletesNewlyCreatedFile() throws {
        let dir = try tempDir()
        let created = dir.appendingPathComponent("new.json")  // 全新檔案
        let badDir = dir.appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let bad = badDir.appendingPathComponent("deep/b.json")  // copyFile 來源不存在 → throw
        let inst = installer(paths: HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir))

        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertThrowsError(try inst.apply([
            .writeJSON(created, Data(#"{"v":1}"#.utf8)),  // 建立新檔
            .copyFile(from: bad, to: dir.appendingPathComponent("c.json")),  // 這步 throw
        ]))
        // 新建的檔案應被回滾刪除
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
    }

    func test_rollbackBareWriteJSONRestoresExistingFileBytes() throws {
        let dir = try tempDir()
        let target = dir.appendingPathComponent("existing.json")
        let original = Data([0x7B, 0x22, 0x76, 0x22, 0x3A, 0x31, 0x7D, 0x0A])
        try original.write(to: target)
        let missing = dir.appendingPathComponent("missing/source.json")
        let inst = installer(paths: HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir))

        XCTAssertThrowsError(try inst.apply([
            .writeJSON(target, Data(#"{"v":2}"#.utf8)),
            .copyFile(from: missing, to: dir.appendingPathComponent("unused.json")),
        ]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func test_rollbackBareWriteJSONDeletesNewFile() throws {
        let dir = try tempDir()
        let target = dir.appendingPathComponent("new-bare.json")
        let missing = dir.appendingPathComponent("missing/source.json")
        let inst = installer(paths: HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir))

        XCTAssertThrowsError(try inst.apply([
            .writeJSON(target, Data(#"{"v":1}"#.utf8)),
            .copyFile(from: missing, to: dir.appendingPathComponent("unused.json")),
        ]))

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func test_rollbackBackupAndWriteJSONRestoreExistingFileBytes() throws {
        let dir = try tempDir()
        let target = dir.appendingPathComponent("backed-up.json")
        let original = Data([0x00, 0x7B, 0x22, 0x76, 0x22, 0x3A, 0x31, 0x7D, 0xFF])
        try original.write(to: target)
        let missing = dir.appendingPathComponent("missing/source.json")
        let inst = installer(paths: HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir))

        XCTAssertThrowsError(try inst.apply([
            .backup(target),
            .writeJSON(target, Data(#"{"v":2}"#.utf8)),
            .copyFile(from: missing, to: dir.appendingPathComponent("unused.json")),
        ]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    // MARK: - installAll / detectAll

    private struct StubAdapter: AgentHookAdapter {
        let kind: AgentActivityProviderKind
        let status: HookStatus
        let mutations: [HookMutation]
        let planThrows: Bool
        func detect(fs: FileSystemReading, paths: HookPaths) -> HookStatus { status }
        func plan(paths: HookPaths) throws -> [HookMutation] {
            if planThrows { throw HookPlanError.malformed("boom") }
            return mutations
        }
    }

    func test_installAllIsolatesFailures() throws {
        let dir = try tempDir()
        let target = dir.appendingPathComponent("ok.json")
        // bundledRelay 需為真實可複製的來源檔（installAll 現在會先落地 relay），
        // 放在獨立子目錄避免與 appSupportHooks 自我巢狀。
        let bundledRelay = dir.appendingPathComponent("bundle/peonping-voidnotch-relay.sh")
        try FileManager.default.createDirectory(
            at: bundledRelay.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/bash\n".utf8).write(to: bundledRelay)
        let paths = HookPaths(home: dir, appSupportHooks: dir, bundledRelay: bundledRelay, bundledPiExtension: dir)
        let failing = StubAdapter(kind: .claude, status: .notInstalled, mutations: [], planThrows: true)
        let succeeding = StubAdapter(
            kind: .codex, status: .notInstalled,
            mutations: [.writeJSON(target, Data(#"{"ok":1}"#.utf8))], planThrows: false
        )
        let inst = HookInstaller(adapters: [failing, succeeding], paths: paths,
                                 clock: { Date(timeIntervalSince1970: 1000) })
        let results = inst.installAll(states: [.claude: .notInstalled, .codex: .notInstalled])

        XCTAssertEqual(results.count, 2)
        let claudeResult = results.first { $0.kind == .claude }
        let codexResult = results.first { $0.kind == .codex }
        XCTAssertEqual(claudeResult?.success, false)
        XCTAssertNotNil(claudeResult?.message)
        XCTAssertEqual(codexResult?.success, true)
        // 第二個 adapter 的落地不因第一個失敗而受阻
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func test_installAllEmptyPlanIsSuccess() throws {
        let dir = try tempDir()
        let paths = HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir)
        let adapter = StubAdapter(kind: .grok, status: .notInstalled, mutations: [], planThrows: false)
        let inst = HookInstaller(adapters: [adapter], paths: paths,
                                 clock: { Date(timeIntervalSince1970: 1000) })
        let results = inst.installAll(states: [.grok: .notInstalled])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .grok)
        XCTAssertEqual(results.first?.success, true)
    }

    func test_installAllSkipsInstalledAndAbsent() throws {
        let dir = try tempDir()
        let paths = HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir)
        // status .installed / .agentAbsent 不應進 plan（planThrows:true 若被呼叫會炸）
        let installed = StubAdapter(kind: .claude, status: .installed, mutations: [], planThrows: true)
        let absent = StubAdapter(kind: .codex, status: .agentAbsent, mutations: [], planThrows: true)
        let inst = HookInstaller(adapters: [installed, absent], paths: paths,
                                 clock: { Date(timeIntervalSince1970: 1000) })
        let results = inst.installAll(states: [.claude: .installed, .codex: .agentAbsent])

        // 兩者皆被跳過，結果陣列為空
        XCTAssertTrue(results.isEmpty)
    }

    func test_detectAllMapsEachAdapter() throws {
        let dir = try tempDir()
        let paths = HookPaths(home: dir, appSupportHooks: dir, bundledRelay: dir, bundledPiExtension: dir)
        let a = StubAdapter(kind: .claude, status: .installed, mutations: [], planThrows: false)
        let b = StubAdapter(kind: .codex, status: .notInstalled, mutations: [], planThrows: false)
        let inst = HookInstaller(adapters: [a, b], paths: paths,
                                 clock: { Date(timeIntervalSince1970: 1000) })
        let fs = StubFS()
        let out = inst.detectAll(fs: fs)

        XCTAssertEqual(out[.claude], .installed)
        XCTAssertEqual(out[.codex], .notInstalled)
    }

    private struct StubFS: FileSystemReading {
        func fileExists(_ url: URL) -> Bool { false }
        func readData(_ url: URL) -> Data? { nil }
    }

    // MARK: - relay 落地（Critical #1 回歸測試）

    /// 讀真實檔案的 FS，用來驅動真正的 ClaudeHookAdapter（而非 StubAdapter）。
    private struct RealFSForTest: FileSystemReading {
        func fileExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        func readData(_ url: URL) -> Data? { try? Data(contentsOf: url) }
    }

    func test_installAllCopiesRelayBeforeClaudeAdapterRuns() throws {
        let dir = try tempDir()
        let home = dir.appendingPathComponent("home", isDirectory: true)
        let appSupportHooks = dir.appendingPathComponent("AppSupport/VoidNotch/hooks", isDirectory: true)
        let bundledRelay = dir.appendingPathComponent("Bundle/hooks/peonping-voidnotch-relay.sh")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: bundledRelay.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 假的 bundled relay 來源（App bundle 裡真正會有的檔案，這裡用假內容代表）
        try Data("#!/bin/bash\necho voidnotch-relay-stub\n".utf8).write(to: bundledRelay)
        // ~/.claude 存在才會被 detect 判為「非 agentAbsent」
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)

        let paths = HookPaths(
            home: home, appSupportHooks: appSupportHooks,
            bundledRelay: bundledRelay, bundledPiExtension: dir.appendingPathComponent("voidnotch.ts"))
        let fs = RealFSForTest()
        let claudeAdapter = ClaudeHookAdapter(fs: fs)
        let inst = HookInstaller(adapters: [claudeAdapter], paths: paths,
                                 clock: { Date(timeIntervalSince1970: 1000) })

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.installedRelay.path))
        let results = inst.installAll(states: [.claude: .notInstalled])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.success, true)
        XCTAssertNil(results.first?.message)
        // relay 必須真的落地到 installedRelay，否則 Claude/Codex/Grok 的 hook 指令會指向不存在的腳本
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.installedRelay.path))
        let relayContent = try String(contentsOf: paths.installedRelay, encoding: .utf8)
        XCTAssertTrue(relayContent.contains("voidnotch-relay-stub"))

        // claude 的 settings.json 也應該實際寫入含 relay marker 的 hook 指令
        let settingsData = try Data(contentsOf: paths.claudeSettings)
        let settingsText = String(data: settingsData, encoding: .utf8) ?? ""
        XCTAssertTrue(settingsText.contains("--voidnotch-relay"))
        XCTAssertTrue(settingsText.contains("--voidnotch-input-broker"))
        XCTAssertTrue(settingsText.contains("AskUserQuestion"))
        // JSONSerialization 會把 "/" 轉義成 "\/"，比對前先還原
        XCTAssertTrue(settingsText.replacingOccurrences(of: "\\/", with: "/").contains(paths.installedRelay.path))

        // detectAll 事後應回報 .installed，證實整條路徑真的接通
        let postStates = inst.detectAll(fs: fs)
        XCTAssertEqual(postStates[.claude], .installed)
    }

    func test_installAllReportsFailureWhenRelaySourceMissing() throws {
        let dir = try tempDir()
        let home = dir.appendingPathComponent("home", isDirectory: true)
        let appSupportHooks = dir.appendingPathComponent("AppSupport/VoidNotch/hooks", isDirectory: true)
        // 故意不建立 bundledRelay 來源檔案 → copyFile 應該 throw
        let bundledRelay = dir.appendingPathComponent("Bundle/hooks/peonping-voidnotch-relay.sh")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)

        let paths = HookPaths(
            home: home, appSupportHooks: appSupportHooks,
            bundledRelay: bundledRelay, bundledPiExtension: dir.appendingPathComponent("voidnotch.ts"))
        let fs = RealFSForTest()
        let inst = HookInstaller(adapters: [ClaudeHookAdapter(fs: fs)], paths: paths,
                                 clock: { Date(timeIntervalSince1970: 1000) })

        let results = inst.installAll(states: [.claude: .notInstalled])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.success, false)
        XCTAssertNotNil(results.first?.message)
        // relay 沒複製到位，claude 的 settings.json 不該被動到
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.claudeSettings.path))
    }
}
