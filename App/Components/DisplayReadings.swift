import Foundation
import SystemMonitor
import VoidNotchKit

/// App 端把三 store 的當下狀態組成 [DisplayReading]（menubar 與 gauge 共用）。
@MainActor
enum DisplayReadings {
    /// 依 items 只讀取所需領域，避免經 `monitor.snapshot` 訂閱全部欄位。
    ///
    /// 不可直接讀 `monitor.snapshot`：該 computed property 會一次存取
    /// cpu／ram／thermal／disk／… 全部 per-domain 屬性，Observation 因而追蹤全部，
    /// 等於退回「任一領域變動就整包失效」的舊行為——例如畫面只顯示電池，
    /// 仍會因 CPU 每秒更新而重繪。
    static func make(items: [DisplayItem],
                     monitor: ObservableSystemMonitor,
                     tokenStore: TokenStore,
                     agentStore: AgentActivityStore,
                     at date: Date) -> [DisplayReading] {
        let ai = DisplayReading.aiUsage(
            from: tokenStore.compactDisplayUsage(at: date),
            displayMode: tokenStore.usageDisplayMode)
        let agent = AgentActivitySummary(
            activeCount: agentStore.activeEventCount,
            attentionCount: agentStore.attentionEventCount)

        // 稀疏組裝：只把 items 真正需要的領域從 monitor 填入，Observation 只追蹤這些讀取。
        var snapshot = SystemSnapshot()
        for item in items {
            switch item {
            case .aiUsage, .agentActivity:
                // 不依賴任何 system 領域，略過。
                continue
            case .system(let kind):
                // 不得加 default：日後新增 SystemMetricKind 時必須在此補對應，
                // 否則編譯失敗，避免靜默沿用空預設值而顯示錯誤讀數。
                switch kind {
                case .cpu: snapshot.cpu = monitor.cpu
                case .memory: snapshot.ram = monitor.ram
                case .disk: snapshot.disk = monitor.disk
                case .network: snapshot.network = monitor.network
                case .battery: snapshot.battery = monitor.battery
                case .temperature: snapshot.thermal = monitor.thermal
                case .health: snapshot.health = monitor.health
                case .host: snapshot.host = monitor.host
                case .processes: snapshot.topProcesses = monitor.topProcesses
                case .gpu: snapshot.gpu = monitor.gpu
                }
            }
        }

        return items.map { $0.reading(snapshot: snapshot, aiUsage: ai, agent: agent) }
    }
}
