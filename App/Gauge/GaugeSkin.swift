import SwiftUI
import VoidNotchKit

/// 浮動儀表的可抽換 UI 框架。免費版內建七段管；Pro 套件日後 register 高級 skin。
@MainActor
protocol GaugeSkin {
    var id: String { get }
    func displayName(language: AppLanguage) -> String
    func makeView(items: [DisplayItem], readings: [DisplayReading]) -> AnyView
}

/// skin 註冊表。register 為對外接縫（Pro 純加法，無 #if PRO）。
@MainActor
final class GaugeSkinRegistry {
    static let shared = GaugeSkinRegistry()
    let defaultSkinID = "seven-segment"
    private var skins: [String: GaugeSkin] = [:]
    private var order: [String] = []

    private init() { register(SevenSegmentSkin()); register(RingsSkin()); register(GlassSkin()) }

    func register(_ skin: GaugeSkin) {
        if skins[skin.id] == nil { order.append(skin.id) }
        skins[skin.id] = skin
    }
    func skin(id: String) -> GaugeSkin? { skins[id] }
    var all: [GaugeSkin] { order.compactMap { skins[$0] } }

    /// 取指定 id，找不到回預設。
    func resolved(id: String?) -> GaugeSkin {
        if let id, let s = skins[id] { return s }
        return skins[defaultSkinID] ?? SevenSegmentSkin()
    }
}
