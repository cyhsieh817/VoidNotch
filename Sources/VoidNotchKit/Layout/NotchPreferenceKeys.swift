import Foundation

public enum NotchCompactPreferenceKey {
    /// `true` means the left compact slot is kept visible; `false` means it collapses into the physical notch.
    public static let leadingPinned = "VoidNotch.compact.leadingPinned"
    /// `true` means the right compact slot is kept visible; `false` means it collapses into the physical notch.
    public static let trailingPinned = "VoidNotch.compact.trailingPinned"
    /// Max content width (pt) for leading compact slot.
    public static let leadingMaxWidth = "VoidNotch.compact.leadingMaxWidth"
    /// Max content width (pt) for trailing compact slot.
    public static let trailingMaxWidth = "VoidNotch.compact.trailingMaxWidth"
    /// Compact content height (pt).
    public static let contentHeight = "VoidNotch.compact.contentHeight"

    public static func side(_ widgetID: String) -> String {
        "VoidNotch.widget.\(widgetID).side"
    }

    public static func maxWidthKey(for side: NotchSide) -> String {
        switch side {
        case .leading: return leadingMaxWidth
        case .trailing: return trailingMaxWidth
        }
    }
}

public enum NotchWidgetPreferenceKey {
    public static func enabled(_ id: String) -> String {
        "VoidNotch.widget.\(id).enabled"
    }
}
