import SwiftUI
import VoidNotchKit

struct SevenSegmentSkin: GaugeSkin {
    let id = "seven-segment"

    func displayName(language: AppLanguage) -> String {
        language == .zhTW ? "數碼管" : "Seven Segment"
    }

    func makeView(items: [DisplayItem], readings: [DisplayReading]) -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                ForEach(Array(zip(items, readings).enumerated()), id: \.offset) { _, pair in
                    SevenSegmentCell(item: pair.0, reading: pair.1)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.55)))
        )
    }
}

private struct SevenSegmentCell: View {
    let item: DisplayItem
    let reading: DisplayReading

    var body: some View {
        VStack(spacing: 2) {
            Text(shortLabel).font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(reading.tintKey.color.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if reading.isNumeric {
                HStack(spacing: 3) {
                    ForEach(Array(SevenSegment.glyphs(for: reading.text).enumerated()), id: \.offset) { _, glyph in
                        SevenSegmentDigit(glyph: glyph, color: reading.tintKey.color)
                    }
                    if !reading.unit.isEmpty {
                        Text(reading.unit).font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(reading.tintKey.color.opacity(0.7))
                    }
                }
            } else {
                // 非數值項（host / AI 標籤）走文字 fallback
                Text(reading.text).font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(reading.tintKey.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(minWidth: 30)
    }

    private var shortLabel: String {
        (reading.label ?? item.label(language: AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)))).uppercased()
    }
}

/// 單一七段管數字：以 Path 畫 7 段，暗段留底色。
private struct SevenSegmentDigit: View {
    let glyph: SevenSegmentGlyph
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let t = min(w, h) * 0.16          // 段厚
            func seg(_ on: Bool, _ path: Path) {
                ctx.fill(path, with: .color(on ? color : color.opacity(0.12)))
            }
            // 依 a..g 幾何畫水平/垂直膠囊段（實作者可用簡化矩形）。
            seg(glyph.a, Self.horizontal(x: t, y: 0, len: w - 2*t, thick: t))
            seg(glyph.b, Self.vertical(x: w - t, y: t, len: (h - 3*t)/2, thick: t))
            seg(glyph.c, Self.vertical(x: w - t, y: h/2 + t/2, len: (h - 3*t)/2, thick: t))
            seg(glyph.d, Self.horizontal(x: t, y: h - t, len: w - 2*t, thick: t))
            seg(glyph.e, Self.vertical(x: 0, y: h/2 + t/2, len: (h - 3*t)/2, thick: t))
            seg(glyph.f, Self.vertical(x: 0, y: t, len: (h - 3*t)/2, thick: t))
            seg(glyph.g, Self.horizontal(x: t, y: h/2 - t/2, len: w - 2*t, thick: t))
        }
        .frame(width: 14, height: 22)
    }

    static func horizontal(x: CGFloat, y: CGFloat, len: CGFloat, thick: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: max(0, len), height: thick), cornerRadius: thick/2)
    }
    static func vertical(x: CGFloat, y: CGFloat, len: CGFloat, thick: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: thick, height: max(0, len)), cornerRadius: thick/2)
    }
}
