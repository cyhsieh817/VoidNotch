//
//  WidgetPreviews.swift — Xcode Preview mock data
//

#if DEBUG
import SwiftUI
import SystemMonitor
import VoidNotchKit

@MainActor
private enum PreviewFixtures {
    static let systemMonitor = ObservableSystemMonitor(
        snapshot: SystemSnapshot(
            cpu: {
                var cpu = CPULoad()
                cpu.total = 0.42
                cpu.user = 0.28
                cpu.system = 0.14
                cpu.idle = 0.58
                cpu.perCore = [0.21, 0.39, 0.64, 0.18, 0.11, 0.08]
                cpu.pCoreCount = 4
                cpu.eCoreCount = 2
                cpu.usagePCores = 0.44
                cpu.usageECores = 0.12
                return cpu
            }(),
            ram: {
                var ram = RAMUsage()
                ram.total = 16 * 1_073_741_824
                ram.used = 10 * 1_073_741_824
                ram.free = 6 * 1_073_741_824
                ram.wired = 2 * 1_073_741_824
                ram.compressed = 1 * 1_073_741_824
                ram.pressure = .normal
                return ram
            }(),
            thermal: ThermalSnapshot(cpu: 48, gpu: 44, soc: 43),
            disk: DiskUsage(mount: "/", totalBytes: 1_000_000_000_000, freeBytes: 320_000_000_000),
            diskIO: DiskIO(readMBps: 2.1, writeMBps: 8.4),
            network: NetworkUsage(interface: "en0", rxMBps: 0.54, txMBps: 0.02),
            battery: {
                var b = BatteryStatus()
                b.isPresent = true
                b.percent = 80
                b.isPluggedIn = true
                b.isCharging = false
                b.cycleCount = 87
                b.maxCapacityPercent = 95
                b.healthLabel = "Healthy"
                return b
            }(),
            gpu: {
                var g = GPUUsage()
                g.name = "Apple M4 Pro"
                g.coreCount = 20
                g.usagePercent = nil
                return g
            }(),
            host: {
                var h = HostInfo()
                h.model = "MacBook Pro"
                h.chip = "Apple M4 Pro"
                h.osVersion = "macOS 26.5"
                h.uptimeSeconds = 39_600
                return h
            }(),
            topProcesses: [
                ProcessSample(pid: 1, name: "Code", cpuPercent: 22.1, memoryBytes: 400_000_000),
                ProcessSample(pid: 2, name: "Chrome", cpuPercent: 11.4, memoryBytes: 800_000_000),
            ],
            health: HealthScore(score: 92, label: "Excellent", issues: [])
        )
    )

    static let tokenStore = TokenStore(providers: [
        ProviderUsage(
            provider: .claude,
            status: .available,
            usedPercent: 37,
            sessionTokens: 1_240_000,
            last30DaysTokens: 12_400_000,
            sessionCostUSD: 1.82,
            last30DaysCostUSD: 18.24,
            updatedAt: Date(),
            sourceLabel: "local JSONL",
            strategyID: "cost-snapshot",
            accountEmail: "dev@example.com",
            accountPlan: "Pro",
            cliVersion: "1.0.42"),
        ProviderUsage(
            provider: .codex,
            status: .available,
            usedPercent: 24,
            sessionTokens: 640_000,
            last30DaysTokens: 7_300_000,
            sessionCostUSD: 0.74,
            last30DaysCostUSD: 8.92,
            updatedAt: Date().addingTimeInterval(-1900),
            sourceLabel: "local sessions",
            strategyID: "cost-snapshot",
            cliVersion: "0.29.0"),
        ProviderUsage(
            provider: .antigravity,
            status: .available,
            usedPercent: 18,
            updatedAt: Date(),
            detailText: "Gemini Models remaining 82% · app",
            usageWindows: [
                ProviderUsageWindow(
                    id: "gemini-5h",
                    title: "Gemini Models",
                    kind: .fiveHour,
                    usedPercent: 18,
                    remainingPercent: 82,
                    windowMinutes: 300,
                    resetsAt: Date().addingTimeInterval(3 * 3600 + 20 * 60)),
                ProviderUsageWindow(
                    id: "gemini-weekly",
                    title: "Gemini Models",
                    kind: .weekly,
                    usedPercent: 42,
                    remainingPercent: 58,
                    windowMinutes: 10080,
                    resetsAt: Date().addingTimeInterval(5 * 24 * 3600 + 7 * 3600)),
                ProviderUsageWindow(
                    id: "claude-gpt-weekly",
                    title: "Claude and GPT",
                    kind: .weekly,
                    usedPercent: 8,
                    remainingPercent: 92,
                    windowMinutes: 10080,
                    resetsAt: Date().addingTimeInterval(6 * 24 * 3600 + 4 * 3600)),
            ],
            sourceLabel: "app",
            strategyID: "antigravity-quota",
            accountEmail: "gemini@example.com",
            accountPlan: "Google AI Pro"),
    ])

    static let agentActivityStore = AgentActivityStore(events: [
        AgentActivityEvent(
            provider: .codex,
            status: .running,
            title: "Refactoring provider dashboard",
            detail: "Editing SwiftUI views",
            workspace: "VoidNotch",
            occurredAt: Date().addingTimeInterval(-180),
            durationSeconds: 180),
        AgentActivityEvent(
            provider: .claude,
            status: .needsInput,
            title: "Permission required",
            detail: "Shell command approval needed",
            workspace: "VoidNotch",
            occurredAt: Date().addingTimeInterval(-620)),
        AgentActivityEvent(
            provider: .antigravity,
            status: .completed,
            title: "UI review completed",
            detail: "Initial layout feedback ready",
            workspace: "VoidNotch",
            occurredAt: Date().addingTimeInterval(-1600),
            durationSeconds: 420),
    ])

    static let widgetRegistry: WidgetRegistry = {
        let defaults = UserDefaults(suiteName: "VoidNotch.Preview.WidgetRegistry") ?? .standard
        let registry = WidgetRegistry(defaults: defaults)
        registry.register(SystemWidget(monitor: systemMonitor))
        registry.register(TokenWidget(store: tokenStore, agentStore: agentActivityStore))
        registry.register(AgentActivityWidget(store: agentActivityStore))
        return registry
    }()
}

#Preview("System Compact") {
    ZStack {
        Color.black
        SystemCompactView(monitor: PreviewFixtures.systemMonitor)
            .padding()
    }
    .frame(width: 180, height: 44)
}

#Preview("System Expanded") {
    SystemExpandedView(monitor: PreviewFixtures.systemMonitor)
        .background(.black.opacity(0.85))
}

#Preview("Token Compact") {
    ZStack {
        Color.black
        AISummaryCapsule(
            tokenStore: PreviewFixtures.tokenStore,
            agentStore: PreviewFixtures.agentActivityStore)
            .padding()
    }
    .frame(width: 160, height: 44)
}

#Preview("Token Expanded") {
    TokenExpandedView(store: PreviewFixtures.tokenStore)
        .background(.black.opacity(0.85))
}

#Preview("Provider Settings") {
    ProviderSettingsView(store: PreviewFixtures.tokenStore, registry: PreviewFixtures.widgetRegistry)
        .background(.black.opacity(0.85))
}

#Preview("Agent Activity Expanded") {
    AgentActivityExpandedView(store: PreviewFixtures.agentActivityStore)
        .background(.black.opacity(0.85))
}
#endif
