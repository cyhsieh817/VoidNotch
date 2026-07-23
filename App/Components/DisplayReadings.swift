import Foundation
import SystemMonitor
import VoidNotchKit

/// App 端把三 store 的當下狀態組成 [DisplayReading]（menubar 與 gauge 共用）。
@MainActor
enum DisplayReadings {
    static func make(items: [DisplayItem],
                     snapshot: SystemSnapshot,
                     tokenStore: TokenStore,
                     agentStore: AgentActivityStore,
                     at date: Date) -> [DisplayReading] {
        let ai = DisplayReading.aiUsage(
            from: tokenStore.compactDisplayUsage(at: date),
            displayMode: tokenStore.usageDisplayMode)
        let agent = AgentActivitySummary(
            activeCount: agentStore.activeEventCount,
            attentionCount: agentStore.attentionEventCount)
        return items.map { $0.reading(snapshot: snapshot, aiUsage: ai, agent: agent) }
    }
}
