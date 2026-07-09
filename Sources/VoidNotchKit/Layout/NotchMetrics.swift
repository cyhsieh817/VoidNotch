import CoreGraphics

/// 瀏海面板幾何（純計算，無 SwiftUI）。座標一律以全域 screen frame 為基準。
public enum NotchMetrics {
    public static let expandedTopMargin: CGFloat = 12
    public static let expandedBottomMargin: CGFloat = 24
    public static let compactSafetyMargin: CGFloat = 4

    /// 展開面板上緣留白。DynamicNotchKit 的 expanded 內容已自動 inset 一個實體劉海高度
    /// （NotchView 對 expandedContent 加 `.safeAreaInset(top: notchSize.height)`），
    /// 故此處只補一個視覺餘量，避免與框架的劉海保留疊成過大空洞。menuBarHeight 保留於簽章
    /// 以利非劉海機型未來微調；目前回傳固定餘量即可貼齊 demo（劉海 ~32 + 餘量 ≈ 40）。
    public static func expandedTopInset(menuBarHeight: CGFloat) -> CGFloat {
        _ = menuBarHeight
        return expandedTopMargin
    }

    /// 展開面板可捲區高度上限。
    ///
    /// 關鍵：DynamicNotchKit 把展開視窗寫死成「半個螢幕高」（`screen.frame.height / 2`，
    /// 見 DynamicNotch.initializeWindow），錨在螢幕頂。容器天花板因此只有半螢幕，不是可視全高。
    /// 內容若超過此天花板會被視窗裁切且捲不到，所以可捲區上限必須以半螢幕扣掉框架與面板 chrome 計算。
    ///
    /// chrome 估值：劉海保留 + 框架上下 safeArea + 面板頂留白/錨點列/分頁列/間距/底 margin。
    public static let expandedWindowChrome: CGFloat = 188
    public static func expandedScrollMaxHeight(screenFrameHeight: CGFloat) -> CGFloat {
        max(160, screenFrameHeight / 2 - expandedWindowChrome)
    }

    /// compact 貼合內容的 panel 矩形：罩住「左側內容 + 瀏海」，右緣止於瀏海右緣，
    /// 讓瀏海右側狀態列完全落在 panel 之外（可見可點）。
    public static func compactPanelRect(
        screenFrame: CGRect,
        notchWidth: CGFloat,
        menuBarHeight: CGFloat,
        leftContentWidth: CGFloat
    ) -> CGRect {
        let midX = screenFrame.midX
        let notchHalf = max(0, notchWidth) / 2
        let leftEdge = midX - notchHalf - max(0, leftContentWidth) - compactSafetyMargin
        let rightEdge = midX + notchHalf
        let width = max(1, rightEdge - leftEdge)
        let height = max(1, menuBarHeight)
        let y = screenFrame.maxY - height
        return CGRect(x: leftEdge, y: y, width: width, height: height)
    }
}
