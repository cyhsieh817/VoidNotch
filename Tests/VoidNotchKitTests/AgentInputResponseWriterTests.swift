import XCTest
@testable import VoidNotchKit

final class AgentInputResponseWriterTests: XCTestCase {
    private func sampleRequest(multiSelect: Bool = false) -> AgentInputRequest {
        AgentInputRequest(
            requestID: UUID(),
            questions: [
                AgentInputQuestion(
                    question: "Pick a color",
                    header: "Color",
                    options: [
                        AgentInputOption(label: "red", description: "Red"),
                        AgentInputOption(label: "blue", description: "Blue"),
                        AgentInputOption(label: "green", description: "Green"),
                    ],
                    multiSelect: multiSelect),
            ])
    }

    /// relay 的 request_id 由 python uuid4() 產生（小寫）。App 端寫回的檔名與欄位都必須是小寫，
    /// 否則 relay 比對不上，會一路空等到 broker timeout。
    private func responseURL(for request: AgentInputRequest) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoidNotch/responses", isDirectory: true)
            .appendingPathComponent(request.requestID.uuidString.lowercased() + ".json")
    }

    func test_write_valid_single_selection_produces_correct_json() throws {
        let request = sampleRequest(multiSelect: false)
        try AgentInputResponseWriter.write(request: request, selections: [0: ["blue"]])

        let destination = responseURL(for: request)
        defer { try? FileManager.default.removeItem(at: destination) }

        let data = try Data(contentsOf: destination)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["request_id"] as? String, request.requestID.uuidString.lowercased())
        let answers = try XCTUnwrap(object["answers"] as? [String: String])
        XCTAssertEqual(answers["Pick a color"], "blue")
    }

    func test_write_uses_lowercased_request_id_matching_relay() throws {
        let request = sampleRequest(multiSelect: false)
        try AgentInputResponseWriter.write(request: request, selections: [0: ["blue"]])

        let destination = responseURL(for: request)
        defer { try? FileManager.default.removeItem(at: destination) }

        // 大小寫不敏感的檔案系統會讓大寫檔名也讀得到，所以檔名要直接比對字串，不能只靠開檔成功。
        let names = try FileManager.default.contentsOfDirectory(
            atPath: destination.deletingLastPathComponent().path)
        XCTAssertTrue(names.contains(request.requestID.uuidString.lowercased() + ".json"))

        let data = try Data(contentsOf: destination)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawID = try XCTUnwrap(object["request_id"] as? String)
        XCTAssertEqual(rawID, rawID.lowercased())
    }

    func test_dismiss_writes_dismissal_without_answers() throws {
        let request = sampleRequest()
        try AgentInputResponseWriter.dismiss(request: request)

        let destination = responseURL(for: request)
        defer { try? FileManager.default.removeItem(at: destination) }

        let data = try Data(contentsOf: destination)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["request_id"] as? String, request.requestID.uuidString.lowercased())
        XCTAssertEqual(object["dismissed"] as? Bool, true)
        XCTAssertNil(object["answers"])
    }

    func test_write_valid_multi_selection_joins_in_option_order() throws {
        let request = sampleRequest(multiSelect: true)
        try AgentInputResponseWriter.write(request: request, selections: [0: ["green", "red"]])

        let destination = responseURL(for: request)
        defer { try? FileManager.default.removeItem(at: destination) }

        let data = try Data(contentsOf: destination)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let answers = try XCTUnwrap(object["answers"] as? [String: String])
        // options order: red, blue, green — selected subset joined with ", "
        XCTAssertEqual(answers["Pick a color"], "red, green")
    }

    func test_write_rejects_empty_selection() {
        let request = sampleRequest()
        XCTAssertThrowsError(
            try AgentInputResponseWriter.write(request: request, selections: [0: []]))
        { error in
            XCTAssertEqual((error as? CocoaError)?.code, .validationMissingMandatoryProperty)
        }
    }

    func test_write_rejects_selection_not_in_options() {
        let request = sampleRequest()
        XCTAssertThrowsError(
            try AgentInputResponseWriter.write(request: request, selections: [0: ["purple"]]))
        { error in
            XCTAssertEqual((error as? CocoaError)?.code, .validationMissingMandatoryProperty)
        }
    }

    func test_write_rejects_multiple_when_not_multiSelect() {
        let request = sampleRequest(multiSelect: false)
        XCTAssertThrowsError(
            try AgentInputResponseWriter.write(request: request, selections: [0: ["red", "blue"]]))
        { error in
            XCTAssertEqual((error as? CocoaError)?.code, .validationMissingMandatoryProperty)
        }
    }

    func test_write_rejects_missing_index() {
        let request = sampleRequest()
        XCTAssertThrowsError(
            try AgentInputResponseWriter.write(request: request, selections: [:]))
        { error in
            XCTAssertEqual((error as? CocoaError)?.code, .validationMissingMandatoryProperty)
        }
    }
}
