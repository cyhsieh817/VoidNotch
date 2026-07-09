import SwiftUI

/// 集中所有視覺常數。Widget view 一律走 Theme,不再寫字面值。
enum Theme {
    enum Colors {
        static let text = Color.white
        static let cpu = Color(red: 0.40, green: 0.78, blue: 0.95)
        static let mem = Color(red: 0.62, green: 0.85, blue: 0.55)
        static let temp = Color(red: 0.95, green: 0.62, blue: 0.40)
        static let warning = Color(red: 0.93, green: 0.36, blue: 0.36)
    }
    enum Metrics {
        static let compactFontSize: CGFloat = 11
        static let openFontSize: CGFloat = 13
        static let hSpacing: CGFloat = 8
        static let hPadding: CGFloat = 10
        static let cornerRadius: CGFloat = 8
    }
    enum Fonts {
        static func compact() -> Font { .system(size: Metrics.compactFontSize, weight: .medium, design: .rounded) }
        static func open() -> Font { .system(size: Metrics.openFontSize, weight: .semibold) }
    }
}
