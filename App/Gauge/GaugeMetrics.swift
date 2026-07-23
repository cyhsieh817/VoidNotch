import Foundation

/// gauge 基準尺寸唯一真相：controller 的 panel 框與 content view 的渲染框共用。
enum GaugeMetrics {
    static let cellWidth: CGFloat = 64
    static let cellSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 20   // 兩側各 10
    static let baseHeight: CGFloat = 64

    private static let scaleKey = "VoidNotch.gauge.scale"

    static func baseSize(itemCount: Int) -> CGSize {
        let count = max(0, itemCount)
        let width = horizontalPadding
            + CGFloat(count) * cellWidth
            + CGFloat(max(0, count - 1)) * cellSpacing
        return CGSize(width: width, height: baseHeight)
    }

    static func scale(from defaults: UserDefaults) -> CGFloat {
        let value = defaults.object(forKey: scaleKey) == nil
            ? 1.0
            : defaults.double(forKey: scaleKey)
        return CGFloat(min(max(value, 0.5), 2.0))
    }
}
