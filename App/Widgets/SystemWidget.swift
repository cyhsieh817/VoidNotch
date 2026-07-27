//
//  SystemWidget.swift — System status widget (CPU/RAM/Disk/Net/Battery/Health)
//
//  EN-first UI strings (L10n). Compact metrics follow SystemMetricPreferences.
//

import SwiftUI
import SystemMonitor
import VoidNotchKit

public struct SystemWidget: NotchWidget {
    public let id = "system"
    public let priority = 10

    let monitor: ObservableSystemMonitor

    public init(monitor: ObservableSystemMonitor) {
        self.monitor = monitor
    }

    public func compactView() -> AnyView { AnyView(SystemCompactView(monitor: monitor)) }
    public func expandedView() -> AnyView { AnyView(SystemExpandedView(monitor: monitor)) }
}

// MARK: - Compact

struct SystemCompactView: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(NotchCompactPreferenceKey.leadingPinned) private var isPinned = true
    /// Bump when any metric preference changes (settings writes same suite).
    @AppStorage(SystemMetricKind.preferenceKey(.cpu)) private var cpuOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.memory)) private var memOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.disk)) private var diskOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.network)) private var netOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.battery)) private var batOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.temperature)) private var tempOn = true

    var body: some View {
        let items = compactItems(
            cpu: monitor.cpu,
            ram: monitor.ram,
            disk: monitor.disk,
            network: monitor.network,
            battery: monitor.battery,
            thermal: monitor.thermal)
        Group {
            if items.isEmpty {
                metric("—", "cpu")
            } else {
                ViewThatFits(in: .horizontal) {
                    // Full selection
                    HStack(spacing: 5) {
                        ForEach(items) { item in
                            metricText(item.text, item.icon)
                        }
                    }
                    // Drop trailing items progressively
                    if items.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(items.dropLast()) { item in
                                metricText(item.text, item.icon)
                            }
                        }
                    }
                    if items.count > 2 {
                        HStack(spacing: 5) {
                            ForEach(items.prefix(2)) { item in
                                metricText(item.text, item.icon)
                            }
                        }
                    }
                    metricText(items[0].text, items[0].icon)
                }
            }
        }
        .font(Theme.Fonts.compact())
        .foregroundStyle(Theme.Colors.text)
        .monospacedDigit()
        .frame(maxWidth: isPinned ? 220 : 120, alignment: .leading)
        .clipped()
    }

    private struct CompactItem: Identifiable {
        let id: String
        let text: String
        let icon: String
    }

    private func compactItems(
        cpu: CPULoad,
        ram: RAMUsage,
        disk: DiskUsage,
        network: NetworkUsage,
        battery: BatteryStatus,
        thermal: ThermalSnapshot
    ) -> [CompactItem] {
        // Touch AppStorage so toggles refresh the view.
        _ = (cpuOn, memOn, diskOn, netOn, batOn, tempOn)
        var items: [CompactItem] = []
        for kind in SystemMetricPreferences.enabledCompactMetrics() {
            switch kind {
            case .cpu:
                items.append(CompactItem(id: kind.rawValue, text: "\(cpu.percent)", icon: kind.iconSystemName))
            case .memory:
                items.append(CompactItem(id: kind.rawValue, text: "\(ram.percent)", icon: kind.iconSystemName))
            case .disk:
                items.append(CompactItem(id: kind.rawValue, text: "\(disk.usedPercent)", icon: kind.iconSystemName))
            case .network:
                items.append(CompactItem(id: kind.rawValue, text: network.compactDownText, icon: "arrow.down"))
            case .battery:
                if battery.isPresent {
                    let pct = battery.percent.map(String.init) ?? "—"
                    items.append(CompactItem(id: kind.rawValue, text: pct, icon: kind.iconSystemName))
                }
            case .temperature:
                if let t = thermal.cpu {
                    items.append(CompactItem(id: kind.rawValue, text: "\(Int(t.rounded()))°", icon: kind.iconSystemName))
                }
            default:
                break
            }
        }
        return items
    }

    private func metric(_ value: String, _ icon: String) -> some View {
        metricText(value, icon)
    }

    private func metricText(_ value: String, _ icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Expanded

struct SystemExpandedView: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(SystemMetricKind.preferenceKey(.cpu)) private var cpuOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.memory)) private var memOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.disk)) private var diskOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.network)) private var netOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.battery)) private var batOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.temperature)) private var tempOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.health)) private var healthOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.host)) private var hostOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.processes)) private var procOn = true
    @AppStorage(SystemMetricKind.preferenceKey(.gpu)) private var gpuOn = true

    var body: some View {
        _ = (cpuOn, memOn, diskOn, netOn, batOn, tempOn, healthOn, hostOn, procOn, gpuOn)

        return VStack(alignment: .leading, spacing: 10) {
            if SystemMetricPreferences.isEnabled(.health) {
                SystemHealthHeader(monitor: monitor)
            }

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 8) {
                if SystemMetricPreferences.isEnabled(.cpu) {
                    SystemCPUCard(monitor: monitor)
                }
                if SystemMetricPreferences.isEnabled(.memory) {
                    SystemMemoryCard(monitor: monitor)
                }
                if SystemMetricPreferences.isEnabled(.disk) {
                    SystemDiskCard(monitor: monitor)
                }
                if SystemMetricPreferences.isEnabled(.network) {
                    SystemNetworkCard(monitor: monitor)
                }
                if SystemMetricPreferences.isEnabled(.battery) {
                    SystemPowerCard(monitor: monitor)
                }
                if SystemMetricPreferences.isEnabled(.temperature) || SystemMetricPreferences.isEnabled(.gpu) {
                    SystemThermalGPUCard(monitor: monitor)
                }
            }

            if SystemMetricPreferences.isEnabled(.host) {
                SystemHostCard(monitor: monitor)
            }

            if SystemMetricPreferences.isEnabled(.processes) {
                SystemTopProcessesCard(monitor: monitor)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .frame(minWidth: 320, maxWidth: 420)
    }

}

private struct SystemHealthHeader: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let health = monitor.health
        let l10n = L10n(rawValue: languageRaw)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.systemTitle).font(.headline)
                Spacer()
                Text("\(health.score)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(health.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(systemHealthColor(health.score))
            }
            if !health.issues.isEmpty {
                Text(health.issues.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SystemCPUCard: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let cpu = monitor.cpu
        let l10n = L10n(rawValue: languageRaw)
        systemSectionCard(title: l10n.cpu, icon: "cpu", fillsRowHeight: true) {
            systemMetricRow(l10n.usage, "\(cpu.percent)%")
            systemMetricRow(l10n.loadAverage, String(format: "%.2f / %.2f / %.2f", cpu.load1, cpu.load5, cpu.load15))
            if let p = cpu.usagePCores, let e = cpu.usageECores {
                systemMetricRow("P/E", "\(Int((p * 100).rounded()))% / \(Int((e * 100).rounded()))%")
            }
        }
    }
}

private struct SystemMemoryCard: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let ram = monitor.ram
        let l10n = L10n(rawValue: languageRaw)
        systemSectionCard(title: l10n.memory, icon: "memorychip", fillsRowHeight: true) {
            systemMetricRow(l10n.usage, "\(ram.percent)%")
            systemMetricRow(l10n.used, "\(ByteFormat.gib(ram.used)) / \(ByteFormat.gib(ram.total))")
            systemMetricRow(l10n.pressure, ram.pressure.label)
            systemMetricRow(l10n.swap, ByteFormat.gib(ram.swap.used))
        }
    }
}

private struct SystemDiskCard: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let disk = monitor.disk
        let diskIO = monitor.diskIO
        let l10n = L10n(rawValue: languageRaw)
        systemSectionCard(title: l10n.disk, icon: "internaldrive", fillsRowHeight: true) {
            systemMetricRow(l10n.usage, "\(disk.usedPercent)%")
            systemMetricRow(l10n.free, ByteFormat.gib(disk.freeBytes))
            systemMetricRow(l10n.diskRead, NetworkUsage.rateText(diskIO.readMBps))
            systemMetricRow(l10n.diskWrite, NetworkUsage.rateText(diskIO.writeMBps))
        }
    }
}

private struct SystemNetworkCard: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let network = monitor.network
        let l10n = L10n(rawValue: languageRaw)
        systemSectionCard(title: l10n.network, icon: "network", fillsRowHeight: true) {
            systemMetricRow(l10n.interface, network.interface ?? "—")
            systemMetricRow(l10n.download, "↓ \(NetworkUsage.rateText(network.rxMBps))")
            systemMetricRow(l10n.upload, "↑ \(NetworkUsage.rateText(network.txMBps))")
        }
    }
}

private struct SystemPowerCard: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let battery = monitor.battery
        let l10n = L10n(rawValue: languageRaw)
        systemSectionCard(title: l10n.power, icon: "battery.100", fillsRowHeight: true) {
            if battery.isPresent {
                systemMetricRow(l10n.level, battery.percent.map { "\($0)%" } ?? "—")
                systemMetricRow(l10n.status, battery.statusText)
                systemMetricRow(l10n.cycles, battery.cycleCount.map(String.init) ?? "—")
                systemMetricRow(l10n.health, battery.healthLabel ?? "—")
            } else {
                systemMetricRow(l10n.status, "N/A")
            }
        }
    }
}

private struct SystemThermalGPUCard: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let thermal = monitor.thermal
        let gpu = monitor.gpu
        let l10n = L10n(rawValue: languageRaw)
        systemSectionCard(title: l10n.thermalGPU, icon: "thermometer.medium", fillsRowHeight: true) {
            if SystemMetricPreferences.isEnabled(.temperature) {
                systemMetricRow(l10n.cpuTemp, thermal.cpu.map { "\(Int($0.rounded()))°C" } ?? "—")
                systemMetricRow(l10n.gpuTemp, thermal.gpu.map { "\(Int($0.rounded()))°C" } ?? "—")
            }
            if SystemMetricPreferences.isEnabled(.gpu) {
                systemMetricRow(l10n.gpu, gpu.name ?? "—")
                systemMetricRow(l10n.gpuUtil, gpu.usagePercent.map { "\(Int($0.rounded()))%" } ?? "—")
            }
        }
    }
}

private struct SystemHostCard: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let host = monitor.host
        let l10n = L10n(rawValue: languageRaw)
        systemSectionCard(title: l10n.host, icon: "desktopcomputer") {
            systemMetricRow(l10n.model, host.model ?? "—")
            systemMetricRow(l10n.chip, host.chip ?? "—")
            systemMetricRow(l10n.uptime, host.uptimeText)
            systemMetricRow(l10n.os, host.osVersion ?? "—")
        }
    }
}

private struct SystemTopProcessesCard: View {
    let monitor: ObservableSystemMonitor
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let topProcesses = monitor.topProcesses
        let l10n = L10n(rawValue: languageRaw)
        systemSectionCard(title: l10n.topProcesses, icon: "list.bullet") {
            if topProcesses.isEmpty {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topProcesses) { proc in
                    HStack {
                        Text(proc.name)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%%", proc.cpuPercent))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }
}

private func systemSectionCard<Content: View>(
    title: String,
    icon: String,
    fillsRowHeight: Bool = false,
    @ViewBuilder content: () -> Content
) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsRowHeight ? .infinity : nil,
            alignment: .topLeading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
}

private func systemMetricRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
}

private func systemHealthColor(_ score: Int) -> Color {
    switch score {
    case 85...100: return .green
    case 65..<85: return .mint
    case 45..<65: return .orange
    default: return .red
    }
}
