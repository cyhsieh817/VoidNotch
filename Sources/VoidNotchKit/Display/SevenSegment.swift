import Foundation

/// 七段管單字位段位狀態。a 上、b 右上、c 右下、d 下、e 左下、f 左上、g 中。
public struct SevenSegmentGlyph: Sendable, Equatable {
    public let a, b, c, d, e, f, g: Bool
    public init(a: Bool, b: Bool, c: Bool, d: Bool, e: Bool, f: Bool, g: Bool) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e; self.f = f; self.g = g
    }
}

/// 字元 → 七段管段位映射（純函式，供 skin 繪製）。
public enum SevenSegment {
    private static let off = SevenSegmentGlyph(a: false, b: false, c: false, d: false, e: false, f: false, g: false)

    public static func glyph(for character: Character) -> SevenSegmentGlyph {
        switch character {
        case "0": return SevenSegmentGlyph(a: true,  b: true,  c: true,  d: true,  e: true,  f: true,  g: false)
        case "1": return SevenSegmentGlyph(a: false, b: true,  c: true,  d: false, e: false, f: false, g: false)
        case "2": return SevenSegmentGlyph(a: true,  b: true,  c: false, d: true,  e: true,  f: false, g: true)
        case "3": return SevenSegmentGlyph(a: true,  b: true,  c: true,  d: true,  e: false, f: false, g: true)
        case "4": return SevenSegmentGlyph(a: false, b: true,  c: true,  d: false, e: false, f: true,  g: true)
        case "5": return SevenSegmentGlyph(a: true,  b: false, c: true,  d: true,  e: false, f: true,  g: true)
        case "6": return SevenSegmentGlyph(a: true,  b: false, c: true,  d: true,  e: true,  f: true,  g: true)
        case "7": return SevenSegmentGlyph(a: true,  b: true,  c: true,  d: false, e: false, f: false, g: false)
        case "8": return SevenSegmentGlyph(a: true,  b: true,  c: true,  d: true,  e: true,  f: true,  g: true)
        case "9": return SevenSegmentGlyph(a: true,  b: true,  c: true,  d: true,  e: false, f: true,  g: true)
        case "-": return SevenSegmentGlyph(a: false, b: false, c: false, d: false, e: false, f: false, g: true)
        default:  return off
        }
    }

    public static func glyphs(for text: String) -> [SevenSegmentGlyph] {
        text.map(glyph(for:))
    }
}
