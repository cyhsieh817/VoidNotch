//
//  CPUReader.swift — CPU 負載讀取（純 Mach syscall）
//
//  移植自 Stats Modules/CPU/readers.swift（MIT）的 read() 核心。
//  整體負載走 host_statistics(HOST_CPU_LOAD_INFO)，逐核走 host_processor_info(PROCESSOR_CPU_LOAD_INFO)，
//  皆與上一輪 tick 差分。去掉 Reader<T> 基底，改為持有狀態的 class。
//

import Foundation

public final class CPUReader {
    // 整體負載的上一輪 ticks
    private var prevLoad: host_cpu_load_info?
    // 逐核的上一輪 ticks（每核 4 個 state）
    private var prevPerCore: [[UInt32]] = []

    // Apple Silicon 效能/效率核數（sysctl perflevel；非 Apple Silicon 回 0）
    private let pCoreCount: Int
    private let eCoreCount: Int

    public init() {
        self.pCoreCount = CPUReader.sysctlInt("hw.perflevel0.logicalcpu")
        self.eCoreCount = CPUReader.sysctlInt("hw.perflevel1.logicalcpu")
    }

    /// 讀取一次 CPU 負載。首次呼叫因無前值，使用率回 0（須第二次起才有差分）。
    public func read() -> CPULoad {
        var load = CPULoad()
        readTotal(into: &load)
        load.perCore = readPerCore()
        load.pCoreCount = pCoreCount
        load.eCoreCount = eCoreCount
        applyCoreSplit(into: &load)
        applyLoadAverage(into: &load)
        return load
    }

    private func applyLoadAverage(into load: inout CPULoad) {
        var avg = [Double](repeating: 0, count: 3)
        guard getloadavg(&avg, 3) == 3 else { return }
        load.load1 = avg[0]
        load.load5 = avg[1]
        load.load15 = avg[2]
    }

    /// 依 perflevel 數量把逐核使用率分群平均。
    /// ⚠️ 排序假設：host_processor_info 前 pCoreCount 個索引為效能核，其後為效率核。
    /// 此為 Apple Silicon 常見慣例，但未經 SystemKit per-core 型別實證；若標籤顛倒，交換兩行即可。
    /// 主機上可用 powermetrics --samplers cpu_power 對核確認。
    private func applyCoreSplit(into load: inout CPULoad) {
        guard pCoreCount > 0, eCoreCount > 0,
              load.perCore.count >= pCoreCount + eCoreCount else { return }
        let pSlice = load.perCore.prefix(pCoreCount)
        let eSlice = load.perCore.suffix(eCoreCount)
        load.usagePCores = pSlice.reduce(0, +) / Double(pCoreCount)
        load.usageECores = eSlice.reduce(0, +) / Double(eCoreCount)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        return result == 0 ? value : 0
    }

    // MARK: - 整體負載

    private func readTotal(into load: inout CPULoad) {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPtr, &size)
            }
        }

        guard result == KERN_SUCCESS else { return }

        defer { prevLoad = info }
        guard let prev = prevLoad else { return }

        // cpu_ticks 是 (UInt32 × CPU_STATE_MAX)，索引：USER=0 SYSTEM=1 IDLE=2 NICE=3
        let userDiff = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let sysDiff  = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idleDiff = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let niceDiff = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)

        let totalTicks = userDiff + sysDiff + idleDiff + niceDiff
        guard totalTicks > 0 else { return }

        load.user = userDiff / totalTicks
        load.system = sysDiff / totalTicks
        load.idle = idleDiff / totalTicks
        load.total = (userDiff + sysDiff + niceDiff) / totalTicks
    }

    // MARK: - 逐核負載

    private func readPerCore() -> [Double] {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo else { return [] }

        defer {
            let size = vm_size_t(UInt(numCpuInfo) * UInt(MemoryLayout<integer_t>.stride))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        let stateCount = Int(CPU_STATE_MAX) // 4
        var current: [[UInt32]] = []
        var usage: [Double] = []
        usage.reserveCapacity(Int(numCPUs))

        for core in 0..<Int(numCPUs) {
            let base = core * stateCount
            let user = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)])
            let ticks = [user, system, idle, nice]
            current.append(ticks)

            if core < prevPerCore.count {
                let prev = prevPerCore[core]
                let userD = Double(user &- prev[0])
                let sysD = Double(system &- prev[1])
                let idleD = Double(idle &- prev[2])
                let niceD = Double(nice &- prev[3])
                let totalD = userD + sysD + idleD + niceD
                usage.append(totalD > 0 ? (userD + sysD + niceD) / totalD : 0)
            } else {
                usage.append(0)
            }
        }

        prevPerCore = current
        return usage
    }
}
