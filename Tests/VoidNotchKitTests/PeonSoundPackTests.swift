import XCTest
@testable import VoidNotchKit

final class PeonSoundPackTests: XCTestCase {
    private var tempPackURL: URL!

    override func setUpWithError() throws {
        tempPackURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotch.PeonSoundPackTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempPackURL, withIntermediateDirectories: true)

        let legal = tempPackURL.appendingPathComponent("ok.aiff")
        try Data([0x00, 0x01, 0x02]).write(to: legal)

        // Sibling outside pack — traversal target
        let outside = tempPackURL.deletingLastPathComponent()
            .appendingPathComponent("VoidNotch.PeonSoundPackTests.outside.\(UUID().uuidString)")
        try Data([0xFF]).write(to: outside)
    }

    override func tearDownWithError() throws {
        if let tempPackURL {
            try? FileManager.default.removeItem(at: tempPackURL)
        }
    }

    private func makePack() -> PeonSoundPack {
        PeonSoundPack(environment: ["VOIDNOTCH_PEON_PACK": tempPackURL.path])
    }

    func test_validatedSoundURL_rejects_path_traversal() {
        let pack = makePack()
        XCTAssertNil(pack.validatedSoundURL(for: "../secret.aiff"))
        XCTAssertNil(pack.validatedSoundURL(for: "../../etc/passwd"))
        XCTAssertNil(pack.validatedSoundURL(for: "subdir/../../escape.aiff"))
        XCTAssertNil(pack.validatedSoundURL(for: "foo/../../../tmp/x"))
    }

    func test_validatedSoundURL_accepts_legal_filename_inside_pack() {
        let pack = makePack()
        let url = pack.validatedSoundURL(for: "ok.aiff")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.lastPathComponent, "ok.aiff")
        XCTAssertTrue(url?.path.hasPrefix(tempPackURL.resolvingSymlinksInPath().path) == true)
    }

    func test_validatedSoundURL_rejects_missing_file_even_if_path_stays_inside() {
        let pack = makePack()
        XCTAssertNil(pack.validatedSoundURL(for: "missing.aiff"))
    }

    func test_categoryName_mapping() {
        let pack = makePack()
        XCTAssertEqual(pack.categoryName(for: .started), "session.start")
        XCTAssertEqual(pack.categoryName(for: .completed), "task.complete")
        XCTAssertEqual(pack.categoryName(for: .needsInput), "input.required")
        XCTAssertEqual(pack.categoryName(for: .failed), "task.error")
        XCTAssertEqual(pack.categoryName(for: .resourceLimit), "resource.limit")
        XCTAssertNil(pack.categoryName(for: .running))
        XCTAssertNil(pack.categoryName(for: .stopped))
    }

    func test_pack_path_override_absolute() {
        let pack = makePack()
        XCTAssertEqual(
            pack.packURL.resolvingSymlinksInPath().standardizedFileURL.path,
            tempPackURL.resolvingSymlinksInPath().standardizedFileURL.path)
    }
}
