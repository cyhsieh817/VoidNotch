import Foundation
import SystemMonitor

/// 單一顯示項目的取數結果。渲染層只吃這個，不碰原始 store / snapshot。
public struct DisplayReading: Sendable, Equatable {
    public var value: Double?      // 數值（%/計數/溫度…），非數值項為 nil
    public var text: String        // 顯示文字
    public var unit: String        // 單位後綴（"%"、"°"、""）
    public var isNumeric: Bool      // 數碼管可否以七段管渲染
    public var tintKey: DisplayTint
    public var label: String?      // 顯示標籤覆寫；nil＝用 item 目錄標籤
    public var progress: Double?   // 0...1 正規化進度；nil＝無進度語意

    public init(
        value: Double?,
        text: String,
        unit: String,
        isNumeric: Bool,
        tintKey: DisplayTint,
        label: String? = nil,
        progress: Double? = nil)
    {
        self.value = value
        self.text = text
        self.unit = unit
        self.isNumeric = isNumeric
        self.tintKey = tintKey
        self.label = label
        self.progress = progress
    }

    /// AI 用量：由 ProviderUsage 的 compactText 組（沿用既有 menubar 顯示語意）。
    public static func aiUsage(from usage: ProviderUsage?, displayMode: TokenUsageDisplayMode) -> DisplayReading {
        guard let usage else {
            return DisplayReading(value: nil, text: "AI N/A", unit: "", isNumeric: false, tintKey: .ai)
        }
        return DisplayReading(
            value: Double(usage.usedPercent),
            text: usage.compactText(for: displayMode),
            unit: "",
            isNumeric: false,          // compactText 可能含供應商標籤，交文字渲染較穩
            tintKey: .ai,
            label: usage.provider.compactDisplayName,
            progress: normalizedProgress(usage.usedPercent))
    }
}

private func normalizedProgress(_ percentage: Int) -> Double {
    min(max(Double(percentage) / 100, 0), 1)
}

public extension DisplayItem {
    /// 純函式取數。aiUsage 由呼叫端（App）以 DisplayReading.aiUsage 組好傳入。
    func reading(snapshot: SystemSnapshot, aiUsage: DisplayReading?, agent: AgentActivitySummary) -> DisplayReading {
        switch self {
        case .aiUsage:
            return aiUsage ?? DisplayReading(value: nil, text: "AI N/A", unit: "", isNumeric: false, tintKey: .ai)

        case .agentActivity:
            let tint: DisplayTint = agent.attentionCount > 0 ? .warning : .agent
            return DisplayReading(
                value: Double(agent.activeCount),
                text: "\(agent.activeCount)", unit: "", isNumeric: true, tintKey: tint)

        case .system(let kind):
            return Self.systemReading(kind, snapshot)
        }
    }

    private static func systemReading(_ kind: SystemMetricKind, _ s: SystemSnapshot) -> DisplayReading {
        func pct(_ v: Int, _ tint: DisplayTint) -> DisplayReading {
            DisplayReading(
                value: Double(v),
                text: "\(v)",
                unit: "%",
                isNumeric: true,
                tintKey: tint,
                progress: normalizedProgress(v))
        }
        func na(_ tint: DisplayTint) -> DisplayReading {
            DisplayReading(value: nil, text: "N/A", unit: "", isNumeric: false, tintKey: tint)
        }
        switch kind {
        case .cpu: return pct(s.cpu.percent, .cpu)
        case .memory: return pct(s.ram.percent, .mem)
        case .disk: return pct(s.disk.usedPercent, .disk)
        case .health:
            return DisplayReading(
                value: Double(s.health.score),
                text: "\(s.health.score)",
                unit: "",
                isNumeric: true,
                tintKey: .health,
                progress: normalizedProgress(s.health.score))
        case .processes: return DisplayReading(value: Double(s.topProcesses.count), text: "\(s.topProcesses.count)", unit: "", isNumeric: true, tintKey: .neutral)
        case .network:
            return DisplayReading(value: s.network.rxMBps, text: s.network.compactDownText, unit: "", isNumeric: false, tintKey: .network)
        case .battery:
            guard let p = s.battery.percent else { return na(.battery) }
            return pct(p, .battery)
        case .temperature:
            guard let t = s.thermal.cpu else { return na(.thermal) }
            let rounded = Int(t.rounded())
            return DisplayReading(value: Double(rounded), text: "\(rounded)", unit: "°", isNumeric: true, tintKey: .thermal)
        case .gpu:
            guard let g = s.gpu.usagePercent else { return na(.gpu) }
            let rounded = Int(g.rounded())
            return pct(rounded, .gpu)
        case .host:
            let short = s.host.model ?? "Mac"
            return DisplayReading(value: nil, text: short, unit: "", isNumeric: false, tintKey: .neutral)
        }
    }
}
