//
//  LaunchdScheduleStore.swift — LaunchAgents 排程監控的 @Observable store
//
//  定期執行 `/bin/launchctl list` 並掃描 LaunchAgents 目錄，
//  透過 VoidNotchKit.LaunchdScheduleScanner 產出 [LaunchdJob] 供 UI 訂閱。
//  Process 與檔案 I/O 一律放非主執行緒；結果回 MainActor 更新。
//

import Foundation
import Observation
import VoidNotchKit

public enum RemovalError: Error, Equatable, Sendable {
    case notRemovable
    case unloadFailed(String)
    case renameFailed(String)
}

@Observable
@MainActor
public final class LaunchdScheduleStore {
    public private(set) var jobs: [LaunchdJob] = []
    public private(set) var lastRefreshed: Date? = nil
    public private(set) var isRefreshing: Bool = false

    @ObservationIgnored private let pollingDriver = PollingDriver()

    public init() {}

    public var homeLaunchAgentsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    public func jobs(in phase: LaunchdJobPhase) -> [LaunchdJob] {
        jobs.filter { $0.phase == phase }
    }

    /// 卸載使用者目錄內的 job，並以 `_DELETE_` 前綴改名封存 plist。
    public func removeJob(_ job: LaunchdJob) async -> Result<Void, RemovalError> {
        let homeLaunchAgents = homeLaunchAgentsURL
        guard LaunchdJobRetirement.isRemovable(
            plistPath: job.plistPath,
            phase: job.phase,
            homeLaunchAgents: homeLaunchAgents,
            isZombie: job.isZombie
        ) else {
            return .failure(.notRemovable)
        }

        let result = await Task.detached(priority: .utility) {
            Self.retireJob(job, homeLaunchAgents: homeLaunchAgents)
        }.value

        await refresh()
        return result
    }

    /// 冪等刷新；掃描進行中重入直接 return。
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let scanned = await Task.detached(priority: .utility) {
            Self.scanJobs()
        }.value

        jobs = scanned
        lastRefreshed = Date()
    }

    /// 以共用 PollingDriver 輪詢；先立即 refresh 一次。重複呼叫會先取消舊 task。
    public func startPolling(interval: TimeInterval) {
        pollingDriver.start(interval: interval) { [weak self] in
            await self?.refresh()
        }
    }

    public func stopPolling() {
        pollingDriver.stop()
    }

    // MARK: - Job retirement

    /// 在 utility 執行緒同步卸載與改名；不使用 shell 或刪除 API。
    nonisolated private static func retireJob(
        _ job: LaunchdJob,
        homeLaunchAgents: URL
    ) -> Result<Void, RemovalError> {
        guard LaunchdJobRetirement.isRemovable(
            plistPath: job.plistPath,
            phase: job.phase,
            homeLaunchAgents: homeLaunchAgents,
            isZombie: job.isZombie
        ) else {
            return .failure(.notRemovable)
        }

        var unloadFailure: String?
        if job.isLoaded {
            unloadFailure = runLaunchctlBootout(label: job.label)
        }

        let sourceURL = URL(fileURLWithPath: job.plistPath)
        let directory = sourceURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        let occupiedFileNames = Set(
            (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
        let archivedFileName = LaunchdJobRetirement.availableArchivedFileName(
            for: sourceURL.lastPathComponent,
            at: Date(),
            occupiedFileNames: occupiedFileNames)

        guard let archivedFileName else {
            return .failure(.renameFailed("封存檔名已達重試上限"))
        }
        let archivedURL = directory.appendingPathComponent(archivedFileName)

        do {
            try FileManager.default.moveItem(at: sourceURL, to: archivedURL)
        } catch {
            return .failure(.renameFailed(error.localizedDescription))
        }

        if let unloadFailure {
            return .failure(.unloadFailed(unloadFailure))
        }
        return .success(())
    }

    /// 固定 `/bin/launchctl`，以 arguments 陣列執行同步 bootout。
    nonisolated private static func runLaunchctlBootout(label: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }

        // 同 runLaunchctlList：先排空 pipe 再等待，維持全檔一致的防死結順序。
        let outputText = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return outputText.isEmpty
                ? "launchctl exited with status \(process.terminationStatus)"
                : outputText
        }
        return nil
    }

    // MARK: - Background scan

    /// 在非主執行緒跑 launchctl + 目錄掃描（供 Task.detached 呼叫）。
    nonisolated private static func scanJobs() -> [LaunchdJob] {
        let output = runLaunchctlList()
        let runtime = LaunchctlListParser.parse(output)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories = [
            home.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
        ]

        let scanner = LaunchdScheduleScanner(fs: RealLaunchdFS())
        return scanner.scan(directories: directories, runtime: runtime)
    }

    /// 固定 `/bin/launchctl list`；慣例比照 AgentActivityWidget.runTmux。
    nonisolated private static func runLaunchctlList() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }

        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 2,
            execute: timeout)
        // 先排空 pipe 再等待程序結束，避免輸出超過 64KB 時與 waitUntilExit 互相死結。
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - File system adapter

/// 以 FileManager 實作 Kit 的目錄讀取協定；目錄不存在回空陣列。
private struct RealLaunchdFS: LaunchdDirectoryReading {
    func plistURLs(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else {
            return []
        }
        return contents.filter {
            $0.pathExtension.lowercased() == "plist" ||
                $0.lastPathComponent.lowercased().hasSuffix(".retired")
        }
    }

    func readData(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }
}
