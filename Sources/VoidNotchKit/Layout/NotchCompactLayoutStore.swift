//
//  NotchCompactLayoutStore.swift — compact side assignment + size prefs
//

import Foundation
import Observation
import CoreGraphics

/// Observable store for notch compact layout preferences (side content + width/height).
@Observable
public final class NotchCompactLayoutStore {
    public private(set) var revision = 0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Side assignment

    public func preferredSide(for widgetID: String) -> NotchSide {
        if let raw = defaults.string(forKey: NotchCompactPreferenceKey.side(widgetID)),
           let side = NotchSide(rawValue: raw)
        {
            return side
        }
        return defaultSide(forWidgetID: widgetID)
    }

    public func setPreferredSide(_ side: NotchSide, for widgetID: String) {
        defaults.set(side.rawValue, forKey: NotchCompactPreferenceKey.side(widgetID))
        bump()
    }

    /// Checking a side moves the widget there; unchecking flips it to the other side.
    public func setWidget(_ widgetID: String, on side: NotchSide, enabled: Bool) {
        if enabled {
            setPreferredSide(side, for: widgetID)
            return
        }
        let other: NotchSide = side == .leading ? .trailing : .leading
        setPreferredSide(other, for: widgetID)
    }

    public func isWidget(_ widgetID: String, on side: NotchSide) -> Bool {
        preferredSide(for: widgetID) == side
    }

    // MARK: - Dimensions

    public func maxWidth(for side: NotchSide) -> CGFloat {
        let key = NotchCompactPreferenceKey.maxWidthKey(for: side)
        if defaults.object(forKey: key) == nil {
            return NotchCompactLayout.defaultWidth(for: side)
        }
        return NotchCompactLayout.clampWidth(CGFloat(defaults.double(forKey: key)))
    }

    public func setMaxWidth(_ width: CGFloat, for side: NotchSide) {
        let clamped = NotchCompactLayout.clampWidth(width)
        defaults.set(Double(clamped), forKey: NotchCompactPreferenceKey.maxWidthKey(for: side))
        bump()
    }

    public var contentHeight: CGFloat {
        if defaults.object(forKey: NotchCompactPreferenceKey.contentHeight) == nil {
            return NotchCompactLayout.defaultHeight
        }
        return NotchCompactLayout.clampHeight(CGFloat(defaults.double(forKey: NotchCompactPreferenceKey.contentHeight)))
    }

    public func setContentHeight(_ height: CGFloat) {
        defaults.set(Double(NotchCompactLayout.clampHeight(height)), forKey: NotchCompactPreferenceKey.contentHeight)
        bump()
    }

    public func isPinned(_ side: NotchSide) -> Bool {
        let key = side == .leading
            ? NotchCompactPreferenceKey.leadingPinned
            : NotchCompactPreferenceKey.trailingPinned
        if defaults.object(forKey: key) == nil {
            return side == .leading
        }
        return defaults.bool(forKey: key)
    }

    public func setPinned(_ pinned: Bool, side: NotchSide) {
        let key = side == .leading
            ? NotchCompactPreferenceKey.leadingPinned
            : NotchCompactPreferenceKey.trailingPinned
        defaults.set(pinned, forKey: key)
        bump()
    }

    private func bump() {
        revision += 1
    }
}
