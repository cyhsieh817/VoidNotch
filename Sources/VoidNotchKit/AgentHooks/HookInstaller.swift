import Foundation

public struct InstallResult: Sendable {
    public let kind: AgentActivityProviderKind
    public let success: Bool
    public let message: String?

    public init(kind: AgentActivityProviderKind, success: Bool, message: String?) {
        self.kind = kind
        self.success = success
        self.message = message
    }
}

public final class HookInstaller {
    private let adapters: [any AgentHookAdapter]
    private let paths: HookPaths
    private let clock: () -> Date
    private let fm = FileManager.default

    public init(adapters: [any AgentHookAdapter], paths: HookPaths, clock: @escaping () -> Date) {
        self.adapters = adapters
        self.paths = paths
        self.clock = clock
    }

    public func detectAll(fs: FileSystemReading) -> [AgentActivityProviderKind: HookStatus] {
        var out: [AgentActivityProviderKind: HookStatus] = [:]
        for a in adapters { out[a.kind] = a.detect(fs: fs, paths: paths) }
        return out
    }

    private enum Undo {
        case restoreBackup(original: URL, backup: URL)
        case restoreContents(URL, Data)
        case deleteCreated(URL)
    }

    /// 落地一組 mutation；任一步失敗即回滾本次所有變更後拋出。
    public func apply(_ mutations: [HookMutation]) throws {
        var undos: [Undo] = []
        do {
            for m in mutations {
                switch m {
                case let .backup(url):
                    guard fm.fileExists(atPath: url.path) else { continue }
                    let bak = backupURL(for: url)
                    try? fm.removeItem(at: bak)
                    try fm.copyItem(at: url, to: bak)
                    undos.append(.restoreBackup(original: url, backup: bak))
                case let .writeJSON(url, data):
                    try ensureParent(url)
                    let existed = fm.fileExists(atPath: url.path)
                    let originalData = existed ? try Data(contentsOf: url) : nil
                    let tmp = url.appendingPathExtension("vntmp")
                    try data.write(to: tmp, options: .atomic)
                    do {
                        if existed {
                            _ = try fm.replaceItemAt(url, withItemAt: tmp)
                            if let originalData {
                                undos.append(.restoreContents(url, originalData))
                            }
                        } else {
                            try fm.moveItem(at: tmp, to: url)
                            undos.append(.deleteCreated(url))
                        }
                    } catch {
                        try? fm.removeItem(at: tmp)  // 未落地的 tmp 不留垃圾
                        throw error
                    }
                case let .copyFile(from, to):
                    guard fm.fileExists(atPath: from.path) else {
                        throw HookPlanError.unreadable("來源不存在：\(from.path)")
                    }
                    try ensureParent(to)
                    if fm.fileExists(atPath: to.path) {
                        let bak = backupURL(for: to)
                        try? fm.removeItem(at: bak)
                        try fm.copyItem(at: to, to: bak)
                        undos.append(.restoreBackup(original: to, backup: bak))
                        try fm.removeItem(at: to)
                    } else {
                        undos.append(.deleteCreated(to))
                    }
                    try fm.copyItem(at: from, to: to)
                case .setDefault:
                    continue  // App 層處理
                }
            }
        } catch {
            // 回滾
            for u in undos.reversed() {
                switch u {
                case let .restoreBackup(original, backup):
                    try? fm.removeItem(at: original)
                    try? fm.copyItem(at: backup, to: original)
                case let .restoreContents(url, data):
                    try? data.write(to: url, options: .atomic)
                case let .deleteCreated(url):
                    try? fm.removeItem(at: url)
                }
            }
            throw error
        }
    }

    public func installAll(states: [AgentActivityProviderKind: HookStatus]) -> [InstallResult] {
        var results: [InstallResult] = []

        // relay 是 Claude/Codex/Grok 共用的基礎設施：三家寫進 settings 的 hook 指令都指向
        // paths.installedRelay，故安裝前必須先把 relay 從 bundle 複製到位一次，否則 hook 執行時
        // 找不到腳本、整條路徑失效（pi 自帶擴充不需 relay）。
        var relayError: String?
        let relayPending = adapters.contains { a in
            guard a.kind == .claude || a.kind == .codex else { return false }
            switch states[a.kind] { case .notInstalled, .conflict: return true; default: return false }
        }
        if relayPending {
            do { try apply([.copyFile(from: paths.bundledRelay, to: paths.installedRelay)]) }
            catch { relayError = "relay 腳本複製失敗：\(error)" }
        }

        for adapter in adapters {
            guard let status = states[adapter.kind] else { continue }
            switch status {
            case .installed, .agentAbsent:
                continue
            case .notInstalled, .conflict:
                // relay 複製失敗時，依賴 relay 的家（claude/codex）不可能運作，直接標記失敗
                if let relayError, adapter.kind == .claude || adapter.kind == .codex {
                    results.append(InstallResult(kind: adapter.kind, success: false, message: relayError))
                    continue
                }
                do {
                    try apply(try adapter.plan(paths: paths))  // 空 plan（grok）→ apply([]) 無操作
                    results.append(InstallResult(kind: adapter.kind, success: true, message: nil))
                } catch {
                    results.append(InstallResult(kind: adapter.kind, success: false, message: "\(error)"))
                }
            }
        }
        return results
    }

    private var backupCounter = 0
    private func backupURL(for url: URL) -> URL {
        let ts = Int(clock().timeIntervalSince1970)
        backupCounter += 1
        return url.appendingPathExtension("voidnotch-bak.\(ts).\(backupCounter)")
    }

    private func ensureParent(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }
}
