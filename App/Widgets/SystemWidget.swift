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
        let s = monitor.snapshot
        let items = compactItems(from: s)
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

    private func compactItems(from s: SystemSnapshot) -> [CompactItem] {
        // Touch AppStorage so toggles refresh the view.
        _ = (cpuOn, memOn, diskOn, netOn, batOn, tempOn)
        var items: [CompactItem] = []
        for kind in SystemMetricPreferences.enabledCompactMetrics() {
            switch kind {
            case .cpu:
                items.append(CompactItem(id: kind.rawValue, text: "\(s.cpu.percent)", icon: kind.iconSystemName))
            case .memory:
                items.append(CompactItem(id: kind.rawValue, text: "\(s.ram.percent)", icon: kind.iconSystemName))
            case .disk:
                items.append(CompactItem(id: kind.rawValue, text: "\(s.disk.usedPercent)", icon: kind.iconSystemName))
            case .network:
                items.append(CompactItem(id: kind.rawValue, text: s.network.compactDownText, icon: "arrow.down"))
            case .battery:
                if s.battery.isPresent {
                    let pct = s.battery.percent.map(String.init) ?? "—"
                    items.append(CompactItem(id: kind.rawValue, text: pct, icon: kind.iconSystemName))
                }
            case .temperature:
                if let t = s.thermal.cpu {
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
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue
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
        let s = monitor.snapshot
        let l10n = L10n(rawValue: languageRaw)
        _ = (cpuOn, memOn, diskOn, netOn, batOn, tempOn, healthOn, hostOn, procOn, gpuOn)

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if SystemMetricPreferences.isEnabled(.health) {
                    healthHeader(s.health, l10n: l10n)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    if SystemMetricPreferences.isEnabled(.cpu) {
                        sectionCard(title: l10n.cpu, icon: "cpu") {
                            metricRow(l10n.usage, "\(s.cpu.percent)%")
                            metricRow(l10n.loadAverage, String(format: "%.2f / %.2f / %.2f", s.cpu.load1, s.cpu.load5, s.cpu.load15))
                            if let p = s.cpu.usagePCores, let e = s.cpu.usageECores {
                                metricRow("P/E", "\(Int((p * 100).rounded()))% / \(Int((e * 100).rounded()))%")
                            }
                        }
                    }
                    if SystemMetricPreferences.isEnabled(.memory) {
                        sectionCard(title: l10n.memory, icon: "memorychip") {
                            metricRow(l10n.usage, "\(s.ram.percent)%")
                            metricRow(l10n.used, "\(ByteFormat.gib(s.ram.used)) / \(ByteFormat.gib(s.ram.total))")
                            metricRow(l10n.pressure, s.ram.pressure.label)
                            metricRow(l10n.swap, ByteFormat.gib(s.ram.swap.used))
                        }
                    }
                    if SystemMetricPreferences.isEnabled(.disk) {
                        sectionCard(title: l10n.disk, icon: "internaldrive") {
                            metricRow(l10n.usage, "\(s.disk.usedPercent)%")
                            metricRow(l10n.free, ByteFormat.gib(s.disk.freeBytes))
                            metricRow(l10n.diskRead, NetworkUsage.rateText(s.diskIO.readMBps))
                            metricRow(l10n.diskWrite, NetworkUsage.rateText(s.diskIO.writeMBps))
                        }
                    }
                    if SystemMetricPreferences.isEnabled(.network) {
                        sectionCard(title: l10n.network, icon: "network") {
                            metricRow(l10n.interface, s.network.interface ?? "—")
                            metricRow(l10n.download, "↓ \(NetworkUsage.rateText(s.network.rxMBps))")
                            metricRow(l10n.upload, "↑ \(NetworkUsage.rateText(s.network.txMBps))")
                        }
                    }
                    if SystemMetricPreferences.isEnabled(.battery) {
                        sectionCard(title: l10n.power, icon: "battery.100") {
                            if s.battery.isPresent {
                                metricRow(l10n.level, s.battery.percent.map { "\($0)%" } ?? "—")
                                metricRow(l10n.status, s.battery.statusText)
                                metricRow(l10n.cycles, s.battery.cycleCount.map(String.init) ?? "—")
                                metricRow(l10n.health, s.battery.healthLabel ?? "—")
                            } else {
                                metricRow(l10n.status, "N/A")
                            }
                        }
                    }
                    if SystemMetricPreferences.isEnabled(.temperature) || SystemMetricPreferences.isEnabled(.gpu) {
                        sectionCard(title: l10n.thermalGPU, icon: "thermometer.medium") {
                            if SystemMetricPreferences.isEnabled(.temperature) {
                                metricRow(l10n.cpuTemp, s.thermal.cpu.map { "\(Int($0.rounded()))°C" } ?? "—")
                                metricRow(l10n.gpuTemp, s.thermal.gpu.map { "\(Int($0.rounded()))°C" } ?? "—")
                            }
                            if SystemMetricPreferences.isEnabled(.gpu) {
                                metricRow(l10n.gpu, s.gpu.name ?? "—")
                                metricRow(l10n.gpuUtil, s.gpu.usagePercent.map { "\(Int($0.rounded()))%" } ?? "—")
                            }
                        }
                    }
                }

                if SystemMetricPreferences.isEnabled(.host) {
                    sectionCard(title: l10n.host, icon: "desktopcomputer") {
                        metricRow(l10n.model, s.host.model ?? "—")
                        metricRow(l10n.chip, s.host.chip ?? "—")
                        metricRow(l10n.uptime, s.host.uptimeText)
                        metricRow(l10n.os, s.host.osVersion ?? "—")
                    }
                }

                if SystemMetricPreferences.isEnabled(.processes) {
                    sectionCard(title: l10n.topProcesses, icon: "list.bullet") {
                        if s.topProcesses.isEmpty {
                            Text("—")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(s.topProcesses) { proc in
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
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 320, maxWidth: 420)
    }

    private func healthHeader(_ health: HealthScore, l10n: L10n) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.systemTitle).font(.headline)
                Spacer()
                Text("\(health.score)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(health.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(healthColor(health.score))
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

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
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

    private func healthColor(_ score: Int) -> Color {
        switch score {
        case 85...100: return .green
        case 65..<85: return .mint
        case 45..<65: return .orange
        default: return .red
        }
    }
}
