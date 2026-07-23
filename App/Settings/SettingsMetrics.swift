import SwiftUI

/// 設定視窗版面的單一真相；禁止在各檢視裡另寫魔數。
enum SettingsMetrics {
    static let inset: CGFloat = 20 // 僅用於頁面內容到視窗邊緣的水平內縮；膠囊、卡片、列等元件內部留白維持各自字面值。
    static let windowWidth: CGFloat = 820
    static let minWindowHeight: CGFloat = 360
    static let maxWindowHeight: CGFloat = 780
    static let sidebarWidth: CGFloat = 260
}
