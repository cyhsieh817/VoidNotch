//
//  vn-probe — SystemMonitor 驗證探針
//
//  用法：swift run vn-probe [取樣次數，預設 5]
//

import Foundation
import SystemMonitor

let samples = CommandLine.arguments.count > 1 ? (Int(CommandLine.arguments[1]) ?? 5) : 5
let manager = SystemMonitorManager()

print("VoidNotch SystemMonitor probe — \(samples) samples, 1s interval")
print(String(repeating: "─", count: 64))

_ = manager.snapshot()
Thread.sleep(forTimeInterval: 1.0)

func fmtTemp(_ d: Double?) -> String { d.map { String(format: "%.1f°C", $0) } ?? "—" }
func pct(_ d: Double?) -> String { d.map { String(format: "%.0f%%", $0 * 100) } ?? "—" }

for i in 1...samples {
    let s = manager.snapshot()
    print("[\(i)] Health \(s.health.score) \(s.health.label)\(s.health.issues.isEmpty ? "" : " · \(s.health.issues.joined(separator: ", "))")")
    print("    CPU \(s.cpu.percent)%  load \(String(format: "%.2f", s.cpu.load1))  P/E \(pct(s.cpu.usagePCores))/\(pct(s.cpu.usageECores))")
    print("    RAM \(s.ram.percent)%  \(ByteFormat.gib(s.ram.used))/\(ByteFormat.gib(s.ram.total))  pressure \(s.ram.pressure.label)  swap \(ByteFormat.gib(s.ram.swap.used))")
    print("    Disk \(s.disk.usedPercent)%  free \(ByteFormat.gib(s.disk.freeBytes))  R \(NetworkUsage.rateText(s.diskIO.readMBps))  W \(NetworkUsage.rateText(s.diskIO.writeMBps))")
    print("    Net \(s.network.interface ?? "—")  ↓\(NetworkUsage.rateText(s.network.rxMBps))  ↑\(NetworkUsage.rateText(s.network.txMBps))  compact \(s.network.compactDownText)")
    if s.battery.isPresent {
        print("    Batt \(s.battery.percent.map(String.init) ?? "—")%  \(s.battery.statusText)  cycles \(s.battery.cycleCount.map(String.init) ?? "—")  \(s.battery.healthLabel ?? "")")
    } else {
        print("    Batt N/A")
    }
    print("    Temp CPU \(fmtTemp(s.thermal.cpu)) GPU \(fmtTemp(s.thermal.gpu))  GPU util \(s.gpu.usagePercent.map { String(format: "%.0f%%", $0) } ?? "—")  \(s.gpu.name ?? "")")
    print("    Host \(s.host.model ?? "—") · \(s.host.chip ?? "—") · up \(s.host.uptimeText)")
    if !s.topProcesses.isEmpty {
        let line = s.topProcesses.prefix(5).map { "\($0.name) \(String(format: "%.1f", $0.cpuPercent))%" }.joined(separator: " · ")
        print("    Top  \(line)")
    }
    print(String(repeating: "─", count: 64))
    if i < samples { Thread.sleep(forTimeInterval: 1.0) }
}
