import SwiftUI
import VoidNotchKit

struct GaugeContentView: View {
    let systemMonitor: ObservableSystemMonitor
    let tokenStore: TokenStore
    let agentStore: AgentActivityStore
    @AppStorage("VoidNotch.gauge.skin") private var skinID = "seven-segment"
    @AppStorage("VoidNotch.gauge.scale") private var scale = 1.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: TokenStore.compactRotationInterval)) { timeline in
            let items = DisplaySelectionStore.items(for: .gauge)
            let readings = DisplayReadings.make(
                items: items, snapshot: systemMonitor.snapshot,
                tokenStore: tokenStore, agentStore: agentStore, at: timeline.date)
            let base = GaugeMetrics.baseSize(itemCount: items.count)
            let clampedScale = CGFloat(min(max(scale, 0.5), 2.0))
            GaugeSkinRegistry.shared.resolved(id: skinID).makeView(items: items, readings: readings)
                .frame(width: base.width, height: base.height)
                .scaleEffect(clampedScale, anchor: .center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
