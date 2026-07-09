//
//  SystemMonitorManager.swift — 統合 readers + 分頻輪詢
//
//  本類刻意保持 SwiftUI-free（可在 CommandLineTools 下編譯驗證）。
//

import Foundation

/// notch 呈現狀態對應的監控活躍度。foreground 高頻、background 中頻、idle 低頻。
public enum MonitorActivityLevel: Sendable {
    case foreground   // 展開或 hover 中
    case background   // compact 常駐
    case idle         // 完全隱藏
}

public final class SystemMonitorManager: @unchecked Sendable {
    public static let minimumPollingInterval: TimeInterval = 1.0

    private let cpuReader = CPUReader()
    private let ramReader = RAMReader()
    private let thermalReader = ThermalReader()
    private let diskReader = DiskReader()
    private let diskIOReader = DiskIOReader()
    private let networkReader = NetworkReader()
    private let batteryReader = BatteryReader()
    private let gpuReader = GPUReader()
    private let hostInfoReader = HostInfoReader()
    private let processReader = ProcessReader(limit: 5)

    private let queue = DispatchQueue(label: "com.voidnotch.systemmonitor")
    private var pollTask: Task<Void, Never>?

    private let intervalQueue = DispatchQueue(label: "com.voidnotch.systemmonitor.interval")
    private var _intervalNanos: UInt64 = UInt64(2.0 * 1_000_000_000)

    // Medium / slow cadence state (seconds)
    private var lastMediumAt: Date = .distantPast
    private var lastSlowAt: Date = .distantPast
    private var cachedDisk = DiskUsage()
    private var cachedBattery = BatteryStatus()
    private var cachedGPU = GPUUsage()
    private var cachedHost = HostInfo()
    private var cachedProcesses: [ProcessSample] = []

    private var intervalNanos: UInt64 { intervalQueue.sync { _intervalNanos } }

    public init() {}

    public static func pollingInterval(for level: MonitorActivityLevel) -> TimeInterval {
        switch level {
        case .foreground: return 1.0
        case .background: return 3.0
        case .idle:       return 10.0
        }
    }

    public func updateInterval(_ interval: TimeInterval) {
        let clamped = Self.clampedPollingInterval(interval)
        if clamped != interval {
            SystemMonitorLog.monitor.warning("Polling interval \(interval, privacy: .public)s clamped to \(clamped, privacy: .public)s")
        }
        intervalQueue.sync { _intervalNanos = UInt64(clamped * 1_000_000_000) }
    }

    public static func clampedPollingInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite, interval >= minimumPollingInterval else {
            return minimumPollingInterval
        }
        return interval
    }

    /// 同步讀取一次完整快照。
    public func snapshot() -> SystemSnapshot {
        queue.sync { buildSnapshot(now: Date(), forceAll: true) }
    }

    public func startPolling(interval: TimeInterval = 2.0, onUpdate: @escaping @Sendable (SystemSnapshot) -> Void) {
        stopPolling()
        updateInterval(interval)
        pollTask = Task { [weak self] in
            _ = self?.snapshot() // prime differentials
            while !Task.isCancelled {
                guard let self else { break }
                try? await Task.sleep(nanoseconds: self.intervalNanos)
                guard !Task.isCancelled else { break }
                let snap = self.queue.sync { self.buildSnapshot(now: Date(), forceAll: false) }
                onUpdate(snap)
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func buildSnapshot(now: Date, forceAll: Bool) -> SystemSnapshot {
        let cpu = cpuReader.read()
        let ram = ramReader.read()
        let thermal = thermalReader.read()
        let diskIO = diskIOReader.read()
        let network = networkReader.read()

        let mediumEvery: TimeInterval = 3
        let slowEvery: TimeInterval = 15

        if forceAll || now.timeIntervalSince(lastMediumAt) >= mediumEvery {
            cachedDisk = diskReader.read()
            cachedProcesses = processReader.read()
            cachedGPU = gpuReader.read()
            lastMediumAt = now
        }
        if forceAll || now.timeIntervalSince(lastSlowAt) >= slowEvery {
            cachedBattery = batteryReader.read()
            cachedHost = hostInfoReader.read(force: forceAll)
            lastSlowAt = now
        } else {
            // Keep uptime fresh even on fast path.
            var host = cachedHost
            host.uptimeSeconds = hostInfoReader.read(force: false).uptimeSeconds
            cachedHost = host
        }

        let health = HealthScorer.score(
            cpuPercent: Double(cpu.percent),
            memoryPercent: Double(ram.percent),
            memoryPressure: ram.pressure,
            diskUsedPercent: Double(cachedDisk.usedPercent),
            diskIOMBps: diskIO.readMBps + diskIO.writeMBps,
            cpuTempC: thermal.cpu,
            battery: cachedBattery,
            uptimeSeconds: cachedHost.uptimeSeconds)

        return SystemSnapshot(
            cpu: cpu,
            ram: ram,
            thermal: thermal,
            disk: cachedDisk,
            diskIO: diskIO,
            network: network,
            battery: cachedBattery,
            gpu: cachedGPU,
            host: cachedHost,
            topProcesses: cachedProcesses,
            health: health,
            collectedAt: now)
    }
}
