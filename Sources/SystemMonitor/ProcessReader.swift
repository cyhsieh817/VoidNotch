//
//  ProcessReader.swift — top processes by CPU (libproc + delta)
//

import Foundation
import Darwin

public final class ProcessReader: @unchecked Sendable {
    private let limit: Int
    private var prevCPU: [pid_t: (total: UInt64, at: Date)] = [:]
    /// 程序名稱快取：processName 走 proc_name/proc_pidpath syscall，
    /// 同一 pid 跨輪重複查詢成本高；只快取成功解析的名稱。
    private var nameCache: [pid_t: String] = [:]
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
        // 輕量候選：迴圈內不取名，避免對數十個過門檻 pid 做 syscall 後卻只留 top-N。
        var candidates: [(pid: pid_t, cpuPercent: Double, memoryBytes: UInt64)] = []
        candidates.reserveCapacity(64)
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
            } else {
                // 首次見到此 pid：可能是系統回收後重用的號碼，舊名稱必須作廢，
                // 否則 top-N 會掛著前一個程序的名字。
                nameCache[pid] = nil
            }
            prevCPU[pid] = (total, now)

            // Keep candidates that use measurable CPU or significant memory.
            if cpuPercent < 0.1 && mem < 80_000_000 { continue }

            candidates.append((pid: pid, cpuPercent: cpuPercent, memoryBytes: mem))
        }

        if prevCPU.count > 3_000 {
            prevCPU = prevCPU.filter { seen.contains($0.key) }
            // 與 prevCPU 一併清理，避免 nameCache 無上限成長。
            nameCache = nameCache.filter { seen.contains($0.key) }
        }

        // 只為 top-N 取名：先依 CPU 排序取 prefix(limit)，再解析名稱組 ProcessSample。
        let top = candidates.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit)
        return top.map { c in
            ProcessSample(
                pid: Int(c.pid),
                name: processName(pid: c.pid),
                cpuPercent: c.cpuPercent,
                memoryBytes: c.memoryBytes)
        }
    }

    /// 解析程序名稱；先查 nameCache，未命中才 syscall。失敗回退 "pid-\(pid)" 但不寫入快取。
    private func processName(pid: pid_t) -> String {
        if let cached = nameCache[pid] {
            return cached
        }
        var name = [CChar](repeating: 0, count: 1_024)
        if proc_name(pid, &name, UInt32(name.count)) > 0 {
            let resolved = decodeCString(name)
            nameCache[pid] = resolved
            return resolved
        }
        var path = [CChar](repeating: 0, count: 4_096)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let resolved = (decodeCString(path) as NSString).lastPathComponent
            nameCache[pid] = resolved
            return resolved
        }
        return "pid-\(pid)"
    }
}
