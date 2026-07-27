import SwiftUI

/// 集中所有視覺常數。Widget view 一律走 Theme,不再寫字面值。
enum Theme {
    enum Colors {
        static let text = Color.white
        static let cpu = Color(red: 0.40, green: 0.78, blue: 0.95)
        static let mem = Color(red: 0.62, green: 0.85, blue: 0.55)
        static let temp = Color(red: 0.95, green: 0.62, blue: 0.40)
        static let warning = Color(red: 0.93, green: 0.36, blue: 0.36)
        static let disk = Color(red: 0.72, green: 0.60, blue: 0.92)
        static let network = Color(red: 0.40, green: 0.85, blue: 0.82)
        static let battery = Color(red: 0.80, green: 0.82, blue: 0.42)
        static let health = Color(red: 0.55, green: 0.80, blue: 0.70)
        static let gpu = Color(red: 0.92, green: 0.55, blue: 0.78)
    }
    enum Metrics {
        static let compactFontSize: CGFloat = 11
        static let openFontSize: CGFloat = 13
        static let cornerRadius: CGFloat = 8
    }
    enum Fonts {
        static func compact() -> Font { .system(size: Metrics.compactFontSize, weight: .medium, design: .rounded) }
        static func open() -> Font { .system(size: Metrics.openFontSize, weight: .semibold) }
    }

    /// 圖表色票：數值經 dataviz `validate_palette.js` 驗證通過。
    /// 禁止未重跑驗證即修改或微調。
    enum Chart {
        /// 固定順序類別色（provider 身分＝索引，不得依排名循環指派）。
        static let slot1 = Color(red: 0.000, green: 0.592, blue: 0.816) // #0097D0
        static let slot2 = Color(red: 0.827, green: 0.400, blue: 0.000) // #D36600
        static let slot3 = Color(red: 0.604, green: 0.431, blue: 0.855) // #9A6EDA
        static let slot4 = Color(red: 0.318, green: 0.624, blue: 0.204) // #519F34
        /// 固定索引取用：`categoryColors[i]`。
        static let categoryColors: [Color] = [slot1, slot2, slot3, slot4]

        /// 熱圖 sequential 四階不透明度（單一 hue，套在 `Theme.Colors.cpu` 上）。
        static let heatmapOpacities: [Double] = [0.38, 0.55, 0.72, 0.92]
    }
}
