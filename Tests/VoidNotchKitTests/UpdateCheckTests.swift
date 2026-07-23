import XCTest
@testable import VoidNotchKit

final class UpdateCheckTests: XCTestCase {
    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(SemverCompare.isNewer(remote: "0.7.0", than: "0.7.0"))
    }

    func testDevelopmentSuffixIsIgnored() {
        XCTAssertFalse(SemverCompare.isNewer(remote: "0.7.0", than: "0.7.0-dev"))
    }

    func testLeadingVIsIgnored() {
        XCTAssertTrue(SemverCompare.isNewer(remote: "v0.8.0", than: "0.7.0"))
    }

    func testNumericComparisonHandlesTwoDigitMinorVersion() {
        XCTAssertTrue(SemverCompare.isNewer(remote: "0.10.0", than: "0.9.9"))
    }

    func testInvalidRemoteVersionIsSafe() {
        XCTAssertFalse(SemverCompare.isNewer(remote: "abc", than: "0.7.0"))
    }

    func testMissingVersionSegmentIsPaddedWithZero() {
        XCTAssertTrue(SemverCompare.isNewer(remote: "1.0", than: "0.9.9"))
    }

    func testAppUpdateInfoDecodesFromVersionJSON() throws {
        let data = Data(
            #"{"version":"0.8.0","url":"https://voidnotch.com/#download","notes":null}"#.utf8)

        let info = try JSONDecoder().decode(AppUpdateInfo.self, from: data)

        XCTAssertEqual(
            info,
            AppUpdateInfo(
                version: "0.8.0",
                url: "https://voidnotch.com/#download",
                notes: nil))
    }
}
