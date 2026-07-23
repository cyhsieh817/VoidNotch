import Foundation

/// 注入目錄讀取能力，掃描 launchd plist 並合併 launchctl runtime 狀態。
public protocol LaunchdDirectoryReading: Sendable {
    func plistURLs(in directory: URL) -> [URL]
    func readData(_ url: URL) -> Data?
}

public struct LaunchdScheduleScanner: Sendable {
    private let fs: any LaunchdDirectoryReading

    public init(fs: any LaunchdDirectoryReading) {
        self.fs = fs
    }

    public func scan(
        directories: [URL],
        runtime: [String: LaunchdRuntimeState]
    ) -> [LaunchdJob] {
        var jobs: [LaunchdJob] = []
        var seenActiveFiles: Set<String> = []

        for directory in directories {
            for url in fs.plistURLs(in: directory) {
                guard let data = fs.readData(url),
                      var job = LaunchdPlistParser.job(fromPlistData: data, plistPath: url.path) else {
                    continue
                }

                let archived = isArchived(url)
                if !archived {
                    guard seenActiveFiles.insert(job.label).inserted else {
                        continue
                    }
                }

                if let state = runtime[job.label] {
                    job.isLoaded = true
                    job.pid = state.pid
                    job.lastExitStatus = state.lastExitStatus
                } else {
                    job.isLoaded = false
                    job.pid = nil
                    job.lastExitStatus = nil
                }

                if archived {
                    job.phase = .archived
                } else if job.isDisabled || !job.isLoaded {
                    job.phase = .paused
                } else {
                    job.phase = .run
                }
                job.isZombie = archived && LaunchdJobRetirement.isLoadableByLaunchd(
                    fileName: url.lastPathComponent)
                jobs.append(job)
            }
        }

        return jobs.sorted { lhs, rhs in
            let leftRank = harnessRank(lhs.harness)
            let rightRank = harnessRank(rhs.harness)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            if lhs.label != rhs.label {
                return lhs.label < rhs.label
            }
            return lhs.plistPath < rhs.plistPath
        }
    }

    private func isArchived(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent
        return fileName.hasPrefix("_DELETE_") || fileName.lowercased().hasSuffix(".retired")
    }

    private func harnessRank(_ harness: AgentHarnessKind) -> Int {
        AgentHarnessKind.allCases.firstIndex(of: harness) ?? AgentHarnessKind.allCases.count
    }
}
