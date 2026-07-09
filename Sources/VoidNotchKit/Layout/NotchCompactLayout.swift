import Foundation
import CoreGraphics

/// Compact notch side assignment + size clamps (pure logic, UserDefaults-agnostic).
public enum NotchCompactLayout {
    public static let minWidth: CGFloat = 48
    public static let maxWidth: CGFloat = 240
    public static let minSideWidth: CGFloat = minWidth
    public static let maxSideWidth: CGFloat = maxWidth
    public static let defaultLeadingWidth: CGFloat = 150
    public static let defaultTrailingWidth: CGFloat = 110

    public static let minHeight: CGFloat = 16
    public static let maxHeight: CGFloat = 36
    public static let defaultHeight: CGFloat = 22

    public static func clampWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultLeadingWidth }
        return min(maxWidth, max(minWidth, value))
    }

    public static func clampHeight(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultHeight }
        return min(maxHeight, max(minHeight, value))
    }

    public static func defaultWidth(for side: NotchSide) -> CGFloat {
        switch side {
        case .leading: return defaultLeadingWidth
        case .trailing: return defaultTrailingWidth
        }
    }
}
