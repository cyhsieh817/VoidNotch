import XCTest
@testable import VoidNotchKit

/// 這組測試釘的是「跨語言契約」：Swift 寫出去的欄位名，必須正是 relay（python）讀進來的那個。
/// 只驗「檔案寫得出來」是假綠——欄位名打錯照樣寫得出檔案，而 relay 會靜默退回 claude-only，
/// codex／pi 的作答從此無聲失效。
final class AgentBrokerCapabilitiesTests: XCTestCase {
    private func decode(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_announce_without_pro_writes_empty_provider_list() throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let destination = AgentBrokerCapabilities.fileURL(support: support)
        XCTAssertTrue(AgentBrokerCapabilities.announce(isPro: false, support: support))

        let json = try decode(at: destination)
        let providers = try XCTUnwrap(json["answerable_providers"] as? [String])
        XCTAssertEqual(providers, [])
        XCTAssertEqual(json["schema_version"] as? Int, AgentBrokerCapabilities.schemaVersion)
    }

    func test_announce_with_pro_writes_all_answerable_providers() throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let destination = AgentBrokerCapabilities.fileURL(support: support)
        XCTAssertTrue(AgentBrokerCapabilities.announce(isPro: true, support: support))

        let json = try decode(at: destination)
        let providers = try XCTUnwrap(json["answerable_providers"] as? [String])
        XCTAssertEqual(providers, ["claude", "codex", "pi"])
        XCTAssertEqual(json["schema_version"] as? Int, AgentBrokerCapabilities.schemaVersion)
    }

    func test_capability_file_lives_where_the_relay_looks_for_it() {
        let support = URL(fileURLWithPath: "/tmp/support")
        XCTAssertEqual(
            AgentBrokerCapabilities.fileURL(support: support).path,
            "/tmp/support/VoidNotch/broker-capabilities.json"
        )
    }

    /// 每個宣告為「可作答」的 provider，都必須真的有人在瀏海 render 得出選項。
    /// 多宣告一個沒實作的 provider，代價是該 agent 被 broker 擋住直到 timeout。
    func test_declares_exactly_the_providers_with_notch_answering() {
        XCTAssertEqual(Set(AgentBrokerCapabilities.answerableProviders), ["claude", "codex", "pi"])
    }
}
