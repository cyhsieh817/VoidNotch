import Foundation

public enum DisplaySurface: String, Sendable, CaseIterable {
    case menubar, gauge

    public var storageKey: String { "VoidNotch.display.\(rawValue).items" }
    var minItems: Int { 1 }
    /// 上限的成因：gauge 面板寬度由項目數推導（GaugeController.contentSize），
    /// menubar 受狀態列可用寬度限制。6 項時 gauge 寬 454pt，仍在合理範圍。
    /// 設為 public：設定頁要顯示「n/6」計數，使用者才知道為何按不動。
    public var maxItems: Int { 6 }
}

/// menubar 與 gauge 兩份獨立選集的持久化（UI-free、可測）。值為穩定字串鍵 JSON 陣列。
public enum DisplaySelectionStore {
    public static let menubarDefault: [DisplayItem] =
        [.system(.cpu), .system(.memory), .aiUsage, .agentActivity]
    public static let gaugeDefault: [DisplayItem] =
        [.system(.cpu), .system(.memory), .system(.temperature), .aiUsage]

    static func defaultItems(_ surface: DisplaySurface) -> [DisplayItem] {
        surface == .gauge ? gaugeDefault : menubarDefault
    }

    public static func items(for surface: DisplaySurface, defaults: UserDefaults = .standard) -> [DisplayItem] {
        guard let data = defaults.data(forKey: surface.storageKey),
              let keys = try? JSONDecoder().decode([String].self, from: data)
        else { return defaultItems(surface) }
        let items = keys.compactMap(DisplayItem.init(storageKey:))
        guard !items.isEmpty else { return defaultItems(surface) }
        return Array(items.prefix(surface.maxItems))
    }

    public static func setItems(_ items: [DisplayItem], for surface: DisplaySurface, defaults: UserDefaults = .standard) {
        setItems(items, for: surface, defaults: defaults, encode: { try JSONEncoder().encode($0) })
    }

    /// 內部／測試用：可注入 encode；失敗時不得寫入（避免 set(nil) 移除 key）。
    static func setItems(
        _ items: [DisplayItem],
        for surface: DisplaySurface,
        defaults: UserDefaults,
        encode: ([String]) throws -> Data
    ) {
        // 去重保序 + 套上下限：空集回退預設，超上限截斷。
        var seen = Set<DisplayItem>()
        var deduped = items.filter { seen.insert($0).inserted }
        if deduped.isEmpty { deduped = defaultItems(surface) }
        let clamped = Array(deduped.prefix(surface.maxItems))
        let keys = clamped.map(\.storageKey)
        // encode 失敗時保留既有 key，不可 set(nil)（會移除該鍵）。
        guard let data = try? encode(keys) else { return }
        defaults.set(data, forKey: surface.storageKey)
    }

    /// 是否可移除某項（守最少 1）。
    public static func canRemove(_ item: DisplayItem, for surface: DisplaySurface, defaults: UserDefaults = .standard) -> Bool {
        let current = items(for: surface, defaults: defaults)
        if current.count <= surface.minItems, current.contains(item) { return false }
        return true
    }

    /// 是否可再加入（守上限）。
    public static func canAdd(for surface: DisplaySurface, defaults: UserDefaults = .standard) -> Bool {
        items(for: surface, defaults: defaults).count < surface.maxItems
    }

    public static func registerDefaults(_ defaults: UserDefaults = .standard) {
        for surface in DisplaySurface.allCases {
            let keys = defaultItems(surface).map(\.storageKey)
            if let data = try? JSONEncoder().encode(keys) {
                defaults.register(defaults: [surface.storageKey: data])
            }
        }
    }
}
