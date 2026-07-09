//
//  WidgetRegistry.swift — widget 註冊表
//
//  ⚠️ Xcode app target 專屬（SwiftUI / Observation）。
//

import SwiftUI
import Observation
import VoidNotchKit

@Observable
public final class WidgetRegistry {
    public private(set) var widgets: [any NotchWidget] = []
    public private(set) var visibilityRevision = 0

    private let defaults: UserDefaults
    public let layout: NotchCompactLayoutStore

    public init(
        defaults: UserDefaults = .standard,
        layout: NotchCompactLayoutStore? = nil)
    {
        self.defaults = defaults
        self.layout = layout ?? NotchCompactLayoutStore(defaults: defaults)
    }

    public func register(_ widget: any NotchWidget) {
        widgets.append(widget)
    }

    /// 依優先權排序（高→低）。
    public var sortedByPriority: [any NotchWidget] {
        widgets.sorted { $0.priority > $1.priority }
    }

    /// Visible widgets, ordered for compact placement and expanded panel rendering.
    public var visibleSortedByPriority: [any NotchWidget] {
        _ = visibilityRevision
        _ = layout.revision
        return sortedByPriority.filter { isWidgetVisible($0) }
    }

    public func widgets(on side: NotchSide) -> [any NotchWidget] {
        visibleSortedByPriority.filter { layout.preferredSide(for: $0.id) == side }
    }

    public func widget(id: String) -> (any NotchWidget)? {
        widgets.first { $0.id == id }
    }

    public func isWidgetVisible(_ widget: any NotchWidget) -> Bool {
        isWidgetVisible(id: widget.id)
    }

    public func isWidgetVisible(id: String) -> Bool {
        let key = NotchWidgetPreferenceKey.enabled(id)
        guard let value = defaults.object(forKey: key) as? Bool else { return true }
        return value
    }

    public func canSetWidget(id: String, visible: Bool) -> Bool {
        if visible { return true }
        guard let widget = widget(id: id) else { return false }
        if widget.isRequiredInSettings { return false }

        let remainingVisibleCount = widgets.filter { candidate in
            candidate.id == id ? false : isWidgetVisible(candidate)
        }.count
        return remainingVisibleCount > 0
    }

    public func setWidget(id: String, visible: Bool) {
        guard canSetWidget(id: id, visible: visible) else { return }
        defaults.set(visible, forKey: NotchWidgetPreferenceKey.enabled(id))
        visibilityRevision += 1
    }
}
