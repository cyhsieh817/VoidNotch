//
//  ObservableSystemMonitor.swift — SystemMonitorManager 的 @Observable 包裝
//
//  ⚠️ Xcode app target 專屬。
//  橋接已驗證的純資料層（Sources/SystemMonitor）→ SwiftUI。
//  widget view 訂閱此物件即自動重繪（dynamicnotchkit-spike §3 證明的 live update 姿勢）。
//

import Foundation
import Observation
import SystemMonitor

@Observable
@MainActor
public final class ObservableSystemMonitor {
    // 將快照拆成監控領域的獨立屬性，讓 Observation 只使實際讀取且變動的領域失效。
    // 輪詢常會帶回未更新領域的舊值；相等時不賦值，才能避免這些視圖無謂重繪。
    public private(set) var cpu: CPULoad
    public private(set) var ram: RAMUsage
    public private(set) var thermal: ThermalSnapshot
    public private(set) var disk: DiskUsage
    public private(set) var diskIO: DiskIO
    public private(set) var network: NetworkUsage
    public private(set) var battery: BatteryStatus
    public private(set) var gpu: GPUUsage
    public private(set) var host: HostInfo
    public private(set) var topProcesses: [ProcessSample]
    public private(set) var health: HealthScore
    public private(set) var collectedAt: Date

    /// 相容既有以整包快照消費資料的呼叫端；Observation 會依實際讀取的領域建立追蹤。
    public var snapshot: SystemSnapshot {
        SystemSnapshot(
            cpu: cpu,
            ram: ram,
            thermal: thermal,
            disk: disk,
            diskIO: diskIO,
            network: network,
            battery: battery,
            gpu: gpu,
            host: host,
            topProcesses: topProcesses,
            health: health,
            collectedAt: collectedAt
        )
    }

    @ObservationIgnored private let manager = SystemMonitorManager()

    public init(snapshot: SystemSnapshot = SystemSnapshot()) {
        cpu = snapshot.cpu
        ram = snapshot.ram
        thermal = snapshot.thermal
        disk = snapshot.disk
        diskIO = snapshot.diskIO
        network = snapshot.network
        battery = snapshot.battery
        gpu = snapshot.gpu
        host = snapshot.host
        topProcesses = snapshot.topProcesses
        health = snapshot.health
        collectedAt = snapshot.collectedAt
    }

    public func start(interval: TimeInterval = 2.0) {
        manager.startPolling(interval: interval) { [weak self] snap in
            Task { @MainActor in
                self?.apply(snap)
            }
        }
    }

    public func stop() {
        manager.stopPolling()
    }

    func setActivityLevel(_ level: MonitorActivityLevel) {
        manager.updateInterval(SystemMonitorManager.pollingInterval(for: level))
    }

    private func apply(_ snapshot: SystemSnapshot) {
        if cpu != snapshot.cpu { cpu = snapshot.cpu }
        if ram != snapshot.ram { ram = snapshot.ram }
        if thermal != snapshot.thermal { thermal = snapshot.thermal }
        if disk != snapshot.disk { disk = snapshot.disk }
        if diskIO != snapshot.diskIO { diskIO = snapshot.diskIO }
        if network != snapshot.network { network = snapshot.network }
        if battery != snapshot.battery { battery = snapshot.battery }
        if gpu != snapshot.gpu { gpu = snapshot.gpu }
        if host != snapshot.host { host = snapshot.host }
        if topProcesses != snapshot.topProcesses { topProcesses = snapshot.topProcesses }
        if health != snapshot.health { health = snapshot.health }

        // 時戳本身代表本次輪詢；即使其餘領域未變，也必須保留最新採集時間。
        collectedAt = snapshot.collectedAt
    }
}
