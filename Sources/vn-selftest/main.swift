//
//  vn-selftest — 自帶斷言的資料層自測（CommandLineTools 可跑）
//
//  與 Tests/SystemMonitorTests 的 XCTest 案例等價，但用極簡 harness，
//  不依賴 XCTest/Testing 模組 → 在僅有 CommandLineTools 的機器上 `swift run vn-selftest` 即可驗證。
//  全綠回 0，任一失敗回 1（可接 CI gate）。
//

import Foundation
import SystemMonitor

var failures = 0
var passed = 0

@MainActor
func check(_ name: String, _ condition: Bool) {
    if condition { passed += 1; print("  ✅ \(name)") }
    else { failures += 1; print("  ❌ \(name)") }
}

func sysctlInt(_ n: String) -> Int {
    var v = 0; var s = MemoryLayout<Int>.size
    return sysctlbyname(n, &v, &s, nil, 0) == 0 ? v : 0
}

print("VoidNotch SystemMonitor 自測")
print(String(repeating: "─", count: 50))

// MARK: 模型純邏輯
print("Models:")
do {
    var ram = RAMUsage(); ram.total = 16_000_000_000; ram.free = 4_000_000_000
    check("ram.usage == 0.75", abs(ram.usage - 0.75) < 0.0001)
    check("ram.percent == 75", ram.percent == 75)
    let zero = RAMUsage()
    check("零總量不除零", zero.usage == 0 && zero.percent == 0)
    var neg = RAMUsage(); neg.used = 1000; neg.wired = 800; neg.compressed = 500
    check("app 記憶體 clamp 至 0", neg.app == 0)
    var cpu = CPULoad(); cpu.total = 0.326
    check("cpu.percent 四捨五入 == 33", cpu.percent == 33)
    check("壓力 rawValue 對映", MemoryPressure(rawValue: 1) == .normal
          && MemoryPressure(rawValue: 4) == .critical && MemoryPressure(rawValue: 3) == nil)
}

// MARK: RAM 對核 sysctl
print("RAMReader vs sysctl:")
do {
    let ram = RAMReader().read()
    let truth = Double(sysctlInt("hw.memsize"))
    check("total == hw.memsize", truth > 0 && abs(ram.total - truth) < 2)
    check("used 落在 (0, total]", ram.used > 0 && ram.used <= ram.total)
    check("percent ∈ [0,100]", (0...100).contains(ram.percent))
    check("used + free ≈ total", abs((ram.used + ram.free) - ram.total) < 2)
    check("swap.used <= swap.total", ram.swap.used <= ram.swap.total + 1)
    check("壓力非 unknown", ram.pressure != .unknown)
}

// MARK: CPU 對核拓撲
print("CPUReader vs sysctl:")
do {
    let reader = CPUReader()
    let first = reader.read()
    check("首次差分基準 total == 0", first.total == 0)
    Thread.sleep(forTimeInterval: 0.3)
    let load = reader.read()
    check("perCore.count == hw.logicalcpu", load.perCore.count == sysctlInt("hw.logicalcpu"))
    check("逐核使用率 ∈ [0,1]", load.perCore.allSatisfy { (0.0...1.0).contains($0) })
    check("total ∈ [0,1]", (0.0...1.0).contains(load.total))
    check("P/E 核數對 sysctl", load.pCoreCount == sysctlInt("hw.perflevel0.logicalcpu")
          && load.eCoreCount == sysctlInt("hw.perflevel1.logicalcpu"))
    if load.pCoreCount > 0 && load.eCoreCount > 0 {
        check("Apple Silicon E/P 平均存在且 ∈ [0,1]",
              (load.usagePCores.map { (0.0...1.0).contains($0) } ?? false)
              && (load.usageECores.map { (0.0...1.0).contains($0) } ?? false))
    }
}

// MARK: 溫度 best-effort
print("ThermalReader best-effort:")
do {
    let reader = ThermalReader()
    let t = reader.read()
    let saneOrNil: (Double?) -> Bool = { $0 == nil || (10.0...120.0).contains($0!) }
    check("溫度 nil 或落在 10–120°C", saneOrNil(t.cpu) && saneOrNil(t.gpu) && saneOrNil(t.soc))
    if t.cpu == nil && t.gpu == nil && t.soc == nil {
        check("溫度失敗時保留 failure reason", reader.lastFailureReason != nil)
    } else {
        check("溫度成功時 failure reason 清空", reader.lastFailureReason == nil)
    }
    let snap = SystemMonitorManager().snapshot()
    check("Manager 快照三層完整", snap.ram.total > 0 && snap.cpu.perCore.count == sysctlInt("hw.logicalcpu"))
}

// MARK: 輪詢 interval 防呆
print("SystemMonitorManager:")
do {
    let min = SystemMonitorManager.minimumPollingInterval
    check("interval 低於下限會 clamp", SystemMonitorManager.clampedPollingInterval(0) == min)
    check("interval NaN 會 clamp", SystemMonitorManager.clampedPollingInterval(.nan) == min)
    check("interval 合法值保留", SystemMonitorManager.clampedPollingInterval(2.5) == 2.5)
}

// MARK: Disk / Net / Health / Status fields
print("Status extensions:")
do {
    let disk = DiskReader().read()
    check("disk total > 0", disk.totalBytes > 0)
    check("disk usedPercent ∈ [0,100]", (0...100).contains(disk.usedPercent))

    let io = DiskIOReader()
    _ = io.read()
    Thread.sleep(forTimeInterval: 0.2)
    let io2 = io.read()
    check("diskIO rates ≥ 0", io2.readMBps >= 0 && io2.writeMBps >= 0)

    let net = NetworkReader()
    _ = net.read()
    Thread.sleep(forTimeInterval: 0.2)
    let net2 = net.read()
    check("network rates ≥ 0", net2.rxMBps >= 0 && net2.txMBps >= 0)
    check("compact down has arrow", net2.compactDownText.hasPrefix("↓"))

    let health = HealthScorer.score(
        cpuPercent: 10, memoryPercent: 40, memoryPressure: .normal,
        diskUsedPercent: 50, diskIOMBps: 1, cpuTempC: 40,
        battery: BatteryStatus(), uptimeSeconds: 100)
    check("health excellent idle", health.score >= 85 && health.label == "Excellent")

    let m = SystemMonitorManager()
    _ = m.snapshot()
    Thread.sleep(forTimeInterval: 0.3)
    let snap = m.snapshot()
    check("snapshot host uptime non-empty", !snap.host.uptimeText.isEmpty)
    check("snapshot health score in range", (0...100).contains(snap.health.score))
    check("snapshot disk total > 0", snap.disk.totalBytes > 0)
}

print(String(repeating: "─", count: 50))
print("結果：\(passed) 通過，\(failures) 失敗")
exit(failures == 0 ? 0 : 1)
