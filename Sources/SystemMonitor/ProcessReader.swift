//
//  ProcessReader.swift — top processes by CPU (libproc + delta)
//

import Foundation
import Darwin

public final class ProcessReader: @unchecked Sendable {
    private let limit: Int
    private var prevCPU: [pid_t: (total: UInt64, at: Date)] = [:]
    private var timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init(limit: Int = 5) {
        self.limit = max(1, min(20, limit))
    }

    public func read() -> [ProcessSample] {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count))
        count = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard count > 0 else { return [] }

        let now = Date()
        let logicalCPU = max(1, Foundation.ProcessInfo.processInfo.processorCount)
        var samples: [ProcessSample] = []
        samples.reserveCapacity(64)
        var seen: Set<pid_t> = []

        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            seen.insert(pid)

            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }

            let total = UInt64(info.pti_total_user) &+ UInt64(info.pti_total_system)
            let mem = UInt64(info.pti_resident_size)
            var cpuPercent = 0.0

            if let prev = prevCPU[pid] {
                let dt = now.timeIntervalSince(prev.at)
                if dt > 0.05 {
                    let deltaTicks = Double(total &- prev.total)
                    let ns = deltaTicks * Double(timebase.numer) / Double(timebase.denom)
                    let cpuSeconds = ns / 1_000_000_000
                    cpuPercent = min(Double(logicalCPU) * 100, (cpuSeconds / dt) * 100)
                }
            }
            prevCPU[pid] = (total, now)

            // Keep candidates that use measurable CPU or significant memory.
            if cpuPercent < 0.1 && mem < 80_000_000 { continue }

            samples.append(ProcessSample(
                pid: Int(pid),
                name: Self.processName(pid: pid),
                cpuPercent: cpuPercent,
                memoryBytes: mem))
        }

        if prevCPU.count > 3_000 {
            prevCPU = prevCPU.filter { seen.contains($0.key) }
        }

        return Array(samples.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
    }

    private static func processName(pid: pid_t) -> String {
        var name = [CChar](repeating: 0, count: 1_024)
        if proc_name(pid, &name, UInt32(name.count)) > 0 {
            return String(cString: name)
        }
        var path = [CChar](repeating: 0, count: 4_096)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            return (String(cString: path) as NSString).lastPathComponent
        }
        return "pid-\(pid)"
    }
}
