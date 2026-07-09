import Foundation

/// 瀏海 compact 兩側。
public enum NotchSide: String, Sendable, Equatable, CaseIterable, Identifiable {
    case leading
    case trailing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .leading: return "Left"
        case .trailing: return "Right"
        }
    }
}

/// 依 widget id 決定預設側別:系統指標在左,其餘(token / agent)在右。
public func defaultSide(forWidgetID id: String) -> NotchSide {
    id == "system" ? .leading : .trailing
}
