import XCTest
import CoreGraphics
@testable import VoidNotchKit

final class NotchMetricsTests: XCTestCase {
    func test_expanded_top_inset_is_visual_margin_only() {
        // DynamicNotchKit 已保留實體劉海高度，故 top inset 只補固定視覺餘量，不再疊 menuBar。
        XCTAssertEqual(NotchMetrics.expandedTopInset(menuBarHeight: 37), 12)
        XCTAssertEqual(NotchMetrics.expandedTopInset(menuBarHeight: 0), 12)
    }

    func test_expanded_scroll_max_height_fits_half_screen_window() {
        // DynamicNotchKit 展開視窗 = 螢幕全高/2；可捲區上限 = 半螢幕 − chrome。
        XCTAssertEqual(NotchMetrics.expandedScrollMaxHeight(screenFrameHeight: 982), 982 / 2 - 188) // 303
        XCTAssertEqual(NotchMetrics.expandedScrollMaxHeight(screenFrameHeight: 300), 160) // clamp 下限
    }

    func test_compact_panel_rect_frees_right_of_notch() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let rect = NotchMetrics.compactPanelRect(
            screenFrame: screen, notchWidth: 200, menuBarHeight: 37, leftContentWidth: 180)
        // midX=756, notchHalf=100, leftEdge=756-100-180-4=472, rightEdge=856
        XCTAssertEqual(rect.minX, 472)
        XCTAssertEqual(rect.maxX, 856)            // 右緣止於瀏海右緣 → 右側狀態列在 panel 外
        XCTAssertEqual(rect.width, 384)
        XCTAssertEqual(rect.height, 37)
        XCTAssertEqual(rect.maxY, 982)            // 貼螢幕頂
    }

    func test_compact_panel_rect_no_notch_uses_content_width() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NotchMetrics.compactPanelRect(
            screenFrame: screen, notchWidth: 0, menuBarHeight: 24, leftContentWidth: 150)
        XCTAssertEqual(rect.maxX, 720)            // midX，無瀏海時右緣止於中線
        XCTAssertEqual(rect.height, 24)
    }
}
