import XCTest
@testable import VoidNotchKit

final class SevenSegmentTests: XCTestCase {
    func test_eight_all_segments_on() {
        let g = SevenSegment.glyph(for: "8")
        XCTAssertEqual(g, SevenSegmentGlyph(a: true, b: true, c: true, d: true, e: true, f: true, g: true))
    }
    func test_one_only_bc() {
        let g = SevenSegment.glyph(for: "1")
        XCTAssertEqual(g, SevenSegmentGlyph(a: false, b: true, c: true, d: false, e: false, f: false, g: false))
    }
    func test_seven_abc() {
        let g = SevenSegment.glyph(for: "7")
        XCTAssertEqual(g, SevenSegmentGlyph(a: true, b: true, c: true, d: false, e: false, f: false, g: false))
    }
    func test_dash_only_g() {
        XCTAssertEqual(SevenSegment.glyph(for: "-"),
                       SevenSegmentGlyph(a: false, b: false, c: false, d: false, e: false, f: false, g: true))
    }
    func test_space_and_unknown_all_off() {
        let off = SevenSegmentGlyph(a: false, b: false, c: false, d: false, e: false, f: false, g: false)
        XCTAssertEqual(SevenSegment.glyph(for: " "), off)
        XCTAssertEqual(SevenSegment.glyph(for: "Z"), off)
    }
    func test_glyphs_maps_each_char() {
        XCTAssertEqual(SevenSegment.glyphs(for: "42").count, 2)
    }
}
