import SwiftUI
import VoidNotchKit

extension DisplayTint {
    /// 語意鍵 → Theme 色。集中一處，menubar 與 gauge skin 共用。
    var color: Color {
        switch self {
        case .cpu: return Theme.Colors.cpu
        case .mem: return Theme.Colors.mem
        case .disk: return Theme.Colors.disk
        case .network: return Theme.Colors.network
        case .battery: return Theme.Colors.battery
        case .thermal: return Theme.Colors.temp
        case .health: return Theme.Colors.health
        case .gpu: return Theme.Colors.gpu
        case .ai: return Theme.Colors.text
        case .agent: return Theme.Colors.cpu
        case .warning: return Theme.Colors.warning
        case .neutral: return Theme.Colors.text
        }
    }
}
