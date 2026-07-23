import XCTest
@testable import VoidNotchKit

final class AppLanguageTests: XCTestCase {
    func test_resolve_known_raw_values() {
        XCTAssertEqual(AppLanguage.resolve("zh-TW"), .zhTW)
        XCTAssertEqual(AppLanguage.resolve("en"), .en)
    }

    func test_resolve_nil_or_unknown_falls_back_to_default() {
        XCTAssertEqual(AppLanguage.resolve(nil), .default)
        XCTAssertEqual(AppLanguage.resolve("ja"), .default)
        XCTAssertEqual(AppLanguage.resolve(""), .default)
    }

    func test_default_is_english() {
        XCTAssertEqual(AppLanguage.default, .en)
    }

    func test_picker_labels_are_distinct() {
        let labels = AppLanguage.allCases.map(\.pickerLabel)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertEqual(AppLanguage.en.pickerLabel, "English")
        XCTAssertEqual(AppLanguage.zhTW.pickerLabel, "繁體中文")
    }
}
