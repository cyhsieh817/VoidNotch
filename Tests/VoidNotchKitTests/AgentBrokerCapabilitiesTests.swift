import XCTest
@testable import VoidNotchKit

/// 這組測試釘的是「跨語言契約」：Swift 寫出去的欄位名，必須正是 relay（python）讀進來的那個。
/// 只驗「檔案寫得出來」是假綠——欄位名打錯照樣寫得出檔案，relay 就會靜默退回它自己的預設值。
/// VoidNotch 不再代答，`answerable_providers` 一律固定空陣列，讓 relay 一律走保守（回終端機）路徑。
final class AgentBrokerCapabilitiesTests: XCTestCase {
    private func decode(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_announce_writes_empty_provider_list() throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let destination = AgentBrokerCapabilities.fileURL(support: support)
        XCTAssertTrue(AgentBrokerCapabilities.announce(support: support))

        let json = try decode(at: destination)
        let providers = try XCTUnwrap(json["answerable_providers"] as? [String])
        XCTAssertEqual(providers, [])
        XCTAssertEqual(json["schema_version"] as? Int, AgentBrokerCapabilities.schemaVersion)
    }

    func test_capability_file_lives_where_the_relay_looks_for_it() {
        let support = URL(fileURLWithPath: "/tmp/support")
        XCTAssertEqual(
            AgentBrokerCapabilities.fileURL(support: support).path,
            "/tmp/support/VoidNotch/broker-capabilities.json"
        )
    }
}
