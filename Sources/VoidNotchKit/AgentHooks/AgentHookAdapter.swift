import Foundation

public protocol AgentHookAdapter: Sendable {
    var kind: AgentActivityProviderKind { get }
    func detect(fs: FileSystemReading, paths: HookPaths) -> HookStatus
    func plan(paths: HookPaths) throws -> [HookMutation]
}

public enum HookPlanError: Error, Equatable {
    case unreadable(String)
    case malformed(String)
}
