//
//  RAMReader.swift — 記憶體用量讀取（純 Mach syscall）
//
//  移植自 Stats Modules/RAM/readers.swift（MIT）。
//  總量走 host_info(HOST_BASIC_INFO).max_mem（取一次即固定），明細走 host_statistics64(HOST_VM_INFO64)。
//  used 公式沿用 Stats：active + inactive + speculative + wired + compressed − purgeable − external。
//

import Foundation

public final class RAMReader {
    private let totalMemory: Double

    public init() {
        self.totalMemory = RAMReader.readTotalMemory()
    }

    public func read() -> RAMUsage {
        var usage = RAMUsage()
        usage.total = totalMemory

        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64()

        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &size)
            }
        }

        guard result == KERN_SUCCESS else { return usage }

        // host_page_size 查詢（避免存取非並發安全的全域 var vm_kernel_page_size）
        var rawPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &rawPageSize)
        let pageSize = Double(rawPageSize)
        let active = Double(stats.active_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize

        let used = active + inactive + speculative + wired + compressed - purgeable - external

        usage.active = active
        usage.inactive = inactive
        usage.wired = wired
        usage.compressed = compressed
        usage.used = max(0, used)
        usage.free = max(0, totalMemory - usage.used)
        usage.pressure = RAMReader.readPressure()
        usage.swap = RAMReader.readSwap()
        return usage
    }

    /// kern.memorystatus_vm_pressure_level → 1 normal / 2 warning / 4 critical。
    private static func readPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard result == 0 else { return .unknown }
        return MemoryPressure(rawValue: Int(level)) ?? .unknown
    }

    /// vm.swapusage → xsw_usage。
    private static func readSwap() -> Swap {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &xsw, &size, nil, 0)
        var swap = Swap()
        guard result == 0 else { return swap }
        swap.total = Double(xsw.xsu_total)
        swap.used = Double(xsw.xsu_used)
        swap.free = Double(xsw.xsu_avail)
        return swap
    }

    private static func readTotalMemory() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_basic_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_basic_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPtr in
                host_info(mach_host_self(), HOST_BASIC_INFO, reboundPtr, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            // fallback：sysctl hw.memsize
            return Double(Foundation.ProcessInfo.processInfo.physicalMemory)
        }
        return Double(info.max_mem)
    }
}
