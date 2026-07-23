import Foundation

public enum HookStatus: Equatable, Sendable {
    case installed
    case notInstalled
    case agentAbsent
    case conflict(String)
}

public enum HookMutation: Equatable, Sendable {
    case backup(URL)
    case writeJSON(URL, Data)
    case copyFile(from: URL, to: URL)
    case setDefault(key: String, boolValue: Bool)
}

public struct HookPaths: Sendable {
    public let home: URL
    public let appSupportHooks: URL
    public let bundledRelay: URL
    public let bundledPiExtension: URL

    public init(home: URL, appSupportHooks: URL, bundledRelay: URL, bundledPiExtension: URL) {
        self.home = home
        self.appSupportHooks = appSupportHooks
        self.bundledRelay = bundledRelay
        self.bundledPiExtension = bundledPiExtension
    }

    /// 安裝後 relay 的落腳路徑
    public var installedRelay: URL { appSupportHooks.appendingPathComponent("peonping-voidnotch-relay.sh") }
    public var installedPiExtension: URL { home.appendingPathComponent(".pi/agent/extensions/voidnotch.ts") }
    public var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
    public var codexHooks: URL { home.appendingPathComponent(".codex/hooks.json") }
    public var grokConfig: URL { home.appendingPathComponent(".grok/config.toml") }
    public var hermesConfig: URL { home.appendingPathComponent(".hermes/config.yaml") }
    /// hermes 的 hook 必須先進這份 allowlist 才會觸發（hooks_auto_accept: false 時）。
    /// 只看 config.yaml 會誤判成「已接通」——設定在、卻靜默不跑。
    public var hermesAllowlist: URL { home.appendingPathComponent(".hermes/shell-hooks-allowlist.json") }
}

public protocol FileSystemReading: Sendable {
    func fileExists(_ url: URL) -> Bool
    func readData(_ url: URL) -> Data?
}
