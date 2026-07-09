//
//  Models.swift — 系統監控資料模型
//
//  移植自 Stats CPU/RAM 等（MIT），擴充 Disk / Network / Battery / Health 等 status 面欄位。
//  全部 Sendable，可跨 actor 傳遞。
//

import Foundation

// MARK: - CPU

/// CPU 負載快照。
public struct CPULoad: Sendable, Equatable {
    /// 整體使用率 0.0–1.0（system + user），主顯示值。
    public var total: Double = 0
    public var system: Double = 0
    public var user: Double = 0
    public var idle: Double = 0
    /// 逐核使用率 0.0–1.0。
    public var perCore: [Double] = []

    // Apple Silicon 效能/效率核分群（無 perflevel 資訊時為 nil）。
    public var usagePCores: Double?
    public var usageECores: Double?
    public var pCoreCount: Int = 0
    public var eCoreCount: Int = 0

    /// 1 / 5 / 15 分鐘 load average（getloadavg）。
    public var load1: Double = 0
    public var load5: Double = 0
    public var load15: Double = 0

    /// P/E 分群依賴「host_processor_info 前段為效能核」的未證實排序假設。
    public var coreSplitIsHeuristic: Bool = true

    public init() {}

    /// 顯示用百分比（0–100，四捨五入）。
    public var percent: Int { Int((total * 100).rounded()) }
}

// MARK: - Memory

/// 記憶體壓力等級（kern.memorystatus_vm_pressure_level）。
public enum MemoryPressure: Int, Sendable {
    case unknown = 0
    case normal = 1
    case warning = 2
    case critical = 4

    public var label: String {
        switch self {
        case .unknown: return "unknown"
        case .normal: return "normal"
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }
}

/// Swap 用量（位元組）。
public struct Swap: Sendable, Equatable {
    public var total: Double = 0
    public var used: Double = 0
    public var free: Double = 0
    public init() {}
}

/// 記憶體使用快照（位元組）。
public struct RAMUsage: Sendable, Equatable {
    public var total: Double = 0
    public var used: Double = 0
    public var free: Double = 0
    public var active: Double = 0
    public var inactive: Double = 0
    public var wired: Double = 0
    public var compressed: Double = 0
    public var pressure: MemoryPressure = .normal
    public var swap: Swap = Swap()

    public init() {}

    /// 使用率 0.0–1.0，主顯示值。
    public var usage: Double { total > 0 ? (total - free) / total : 0 }
    public var percent: Int { Int((usage * 100).rounded()) }

    /// app 記憶體 = used − wired − compressed。
    public var app: Double { max(0, used - wired - compressed) }
}

// MARK: - Thermal

/// 溫度快照（攝氏）。任一可為 nil（該感測器不可得）。
public struct ThermalSnapshot: Sendable, Equatable {
    public var cpu: Double?
    public var gpu: Double?
    public var soc: Double?

    public init(cpu: Double? = nil, gpu: Double? = nil, soc: Double? = nil) {
        self.cpu = cpu
        self.gpu = gpu
        self.soc = soc
    }
}

// MARK: - Disk

public struct DiskUsage: Sendable, Equatable {
    public var mount: String = "/"
    public var totalBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var usedBytes: UInt64 = 0
    public var usedPercent: Int = 0

    public init() {}

    public init(mount: String, totalBytes: UInt64, freeBytes: UInt64) {
        self.mount = mount
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        if totalBytes > 0 {
            self.usedPercent = min(100, max(0, Int((Double(usedBytes) / Double(totalBytes) * 100).rounded())))
        } else {
            self.usedPercent = 0
        }
    }

    public var freePercent: Int { max(0, 100 - usedPercent) }
}

public struct DiskIO: Sendable, Equatable {
    /// Read rate in MB/s.
    public var readMBps: Double = 0
    /// Write rate in MB/s.
    public var writeMBps: Double = 0

    public init() {}

    public init(readMBps: Double, writeMBps: Double) {
        self.readMBps = max(0, readMBps)
        self.writeMBps = max(0, writeMBps)
    }
}

// MARK: - Network

public struct NetworkUsage: Sendable, Equatable {
    public var interface: String?
    /// Download rate MB/s.
    public var rxMBps: Double = 0
    /// Upload rate MB/s.
    public var txMBps: Double = 0

    public init() {}

    public init(interface: String?, rxMBps: Double, txMBps: Double) {
        self.interface = interface
        self.rxMBps = max(0, rxMBps)
        self.txMBps = max(0, txMBps)
    }

    /// Compact slot text, e.g. "↓0.5M" / "↓128K".
    public var compactDownText: String {
        "↓\(Self.compactRate(rxMBps))"
    }

    public static func compactRate(_ mBps: Double) -> String {
        let bytesPerSec = mBps * 1_048_576
        if bytesPerSec < 1_024 {
            return "0K"
        }
        if bytesPerSec < 1_048_576 {
            return "\(Int((bytesPerSec / 1_024).rounded()))K"
        }
        let mb = bytesPerSec / 1_048_576
        if mb < 10 {
            return String(format: "%.1fM", mb)
        }
        return "\(Int(mb.rounded()))M"
    }

    public static func rateText(_ mBps: Double) -> String {
        if mBps < 0.001 {
            return "0 MB/s"
        }
        if mBps < 1 {
            return String(format: "%.0f KB/s", mBps * 1_024)
        }
        return String(format: "%.2f MB/s", mBps)
    }
}

// MARK: - Battery

public struct BatteryStatus: Sendable, Equatable {
    public var isPresent: Bool = false
    public var percent: Int?
    public var isCharging: Bool?
    public var isPluggedIn: Bool?
    public var timeRemainingMinutes: Int?
    public var cycleCount: Int?
    public var maxCapacityPercent: Int?
    /// Healthy / Fair / Service Soon / unknown
    public var healthLabel: String?

    public init() {}

    public var statusText: String {
        guard isPresent else { return "N/A" }
        if isCharging == true { return "Charging" }
        if isPluggedIn == true { return "AC Power" }
        return "Battery"
    }
}

// MARK: - GPU

public struct GPUUsage: Sendable, Equatable {
    public var name: String?
    public var coreCount: Int?
    /// 0–100 when known; nil = unsupported / unavailable (never invent 0 as idle).
    public var usagePercent: Double?
    public var isSupported: Bool = false

    public init() {}
}

// MARK: - Process / Host / Health

public struct ProcessSample: Sendable, Equatable, Identifiable {
    public var pid: Int
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public var id: Int { pid }

    public init(pid: Int, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct HostInfo: Sendable, Equatable {
    public var model: String?
    public var chip: String?
    public var osVersion: String?
    public var uptimeSeconds: UInt64 = 0
    public var logicalCPU: Int = 0
    public var totalMemoryBytes: UInt64 = 0

    public init() {}

    public var uptimeText: String {
        let secs = uptimeSeconds
        let days = secs / 86_400
        let hours = (secs % 86_400) / 3_600
        let mins = (secs % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

public struct HealthScore: Sendable, Equatable {
    public var score: Int = 100
    /// Excellent / Good / Fair / Needs Attention
    public var label: String = "Excellent"
    public var issues: [String] = []

    public init() {}

    public init(score: Int, label: String, issues: [String] = []) {
        self.score = min(100, max(0, score))
        self.label = label
        self.issues = issues
    }
}

// MARK: - Snapshot

/// 統一系統快照，供 widget 消費。
public struct SystemSnapshot: Sendable, Equatable {
    public var cpu: CPULoad
    public var ram: RAMUsage
    public var thermal: ThermalSnapshot
    public var disk: DiskUsage
    public var diskIO: DiskIO
    public var network: NetworkUsage
    public var battery: BatteryStatus
    public var gpu: GPUUsage
    public var host: HostInfo
    public var topProcesses: [ProcessSample]
    public var health: HealthScore
    public var collectedAt: Date

    public init(
        cpu: CPULoad = .init(),
        ram: RAMUsage = .init(),
        thermal: ThermalSnapshot = .init(),
        disk: DiskUsage = .init(),
        diskIO: DiskIO = .init(),
        network: NetworkUsage = .init(),
        battery: BatteryStatus = .init(),
        gpu: GPUUsage = .init(),
        host: HostInfo = .init(),
        topProcesses: [ProcessSample] = [],
        health: HealthScore = .init(),
        collectedAt: Date = Date())
    {
        self.cpu = cpu
        self.ram = ram
        self.thermal = thermal
        self.disk = disk
        self.diskIO = diskIO
        self.network = network
        self.battery = battery
        self.gpu = gpu
        self.host = host
        self.topProcesses = topProcesses
        self.health = health
        self.collectedAt = collectedAt
    }
}

// MARK: - Byte formatting helpers

public enum ByteFormat {
    public static func gib(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    public static func gib(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_073_741_824)
    }
}
