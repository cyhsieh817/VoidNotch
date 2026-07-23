import XCTest
import SystemMonitor
@testable import VoidNotchKit

final class DisplayReadingTests: XCTestCase {
    private func snapshot() -> SystemSnapshot {
        var cpu = CPULoad(); cpu.total = 0.42
        var ram = RAMUsage(); ram.total = 100; ram.free = 32   // usage 0.68 → 68%
        var thermal = ThermalSnapshot(cpu: 54.4)
        var health = HealthScore(score: 88, label: "Good")
        var snap = SystemSnapshot(cpu: cpu, ram: ram, thermal: thermal, health: health)
        return snap
    }

    private let noAgent = AgentActivitySummary(activeCount: 0, attentionCount: 0)

    func test_cpu_numeric_percent() {
        let r = DisplayItem.system(.cpu).reading(snapshot: snapshot(), aiUsage: nil, agent: noAgent)
        XCTAssertEqual(r.value, 42)
        XCTAssertEqual(r.text, "42")
        XCTAssertEqual(r.unit, "%")
        XCTAssertTrue(r.isNumeric)
        XCTAssertEqual(r.tintKey, .cpu)
    }

    func test_memory_percent() {
        let r = DisplayItem.system(.memory).reading(snapshot: snapshot(), aiUsage: nil, agent: noAgent)
        XCTAssertEqual(r.value, 68)
        XCTAssertTrue(r.isNumeric)
    }

    func test_temperature_present_is_numeric() {
        let r = DisplayItem.system(.temperature).reading(snapshot: snapshot(), aiUsage: nil, agent: noAgent)
        XCTAssertEqual(r.value, 54)          // 四捨五入
        XCTAssertEqual(r.unit, "°")
        XCTAssertTrue(r.isNumeric)
    }

    func test_nil_sensor_falls_back_to_NA_non_numeric() {
        // 無溫度感測器
        var snap = snapshot(); snap.thermal = ThermalSnapshot(cpu: nil)
        let r = DisplayItem.system(.temperature).reading(snapshot: snap, aiUsage: nil, agent: noAgent)
        XCTAssertNil(r.value)
        XCTAssertEqual(r.text, "N/A")
        XCTAssertFalse(r.isNumeric)
    }

    func test_host_is_non_numeric_text() {
        let r = DisplayItem.system(.host).reading(snapshot: snapshot(), aiUsage: nil, agent: noAgent)
        XCTAssertNil(r.value)
        XCTAssertFalse(r.isNumeric)
    }

    func test_agent_activity_uses_active_count_and_warning_tint() {
        let agent = AgentActivitySummary(activeCount: 3, attentionCount: 1)
        let r = DisplayItem.agentActivity.reading(snapshot: snapshot(), aiUsage: nil, agent: agent)
        XCTAssertEqual(r.value, 3)
        XCTAssertEqual(r.text, "3")
        XCTAssertTrue(r.isNumeric)
        XCTAssertEqual(r.tintKey, .warning)   // attentionCount > 0
    }

    func test_agent_activity_agent_tint_when_no_attention() {
        let agent = AgentActivitySummary(activeCount: 2, attentionCount: 0)
        let r = DisplayItem.agentActivity.reading(snapshot: snapshot(), aiUsage: nil, agent: agent)
        XCTAssertEqual(r.tintKey, .agent)
    }

    func test_aiUsage_passthrough() {
        let ai = DisplayReading(value: nil, text: "GPT 55%", unit: "", isNumeric: false, tintKey: .ai)
        let r = DisplayItem.aiUsage.reading(snapshot: snapshot(), aiUsage: ai, agent: noAgent)
        XCTAssertEqual(r, ai)
    }

    func test_aiUsage_nil_falls_back() {
        let r = DisplayItem.aiUsage.reading(snapshot: snapshot(), aiUsage: nil, agent: noAgent)
        XCTAssertEqual(r.text, "AI N/A")
        XCTAssertFalse(r.isNumeric)
        XCTAssertEqual(r.tintKey, .ai)
    }

    func test_aiUsage_sets_compact_provider_label() {
        let usage = ProviderUsage(provider: .antigravity)
        let r = DisplayReading.aiUsage(from: usage, displayMode: .used)

        XCTAssertEqual(r.label, usage.provider.compactDisplayName)
    }

    func test_aiUsage_nil_has_no_label() {
        let r = DisplayReading.aiUsage(from: nil, displayMode: .used)

        XCTAssertNil(r.label)
        XCTAssertEqual(r.text, "AI N/A")
    }

    func test_display_reading_init_without_label_is_backward_compatible() {
        let r = DisplayReading(value: nil, text: "text", unit: "", isNumeric: false, tintKey: .neutral)

        XCTAssertNil(r.label)
    }

    func test_cpu_percent_sets_normalized_progress() {
        let r = DisplayItem.system(.cpu).reading(snapshot: snapshot(), aiUsage: nil, agent: noAgent)

        XCTAssertEqual(r.progress ?? -1, 0.42, accuracy: 0.001)
    }

    func test_temperature_has_no_progress_semantics() {
        let r = DisplayItem.system(.temperature).reading(snapshot: snapshot(), aiUsage: nil, agent: noAgent)

        XCTAssertNil(r.progress)
    }

    func test_aiUsage_sets_normalized_progress_and_nil_usage_does_not() {
        let usage = ProviderUsage(provider: .antigravity, usedPercent: 70)
        let reading = DisplayReading.aiUsage(from: usage, displayMode: .used)
        let noUsage = DisplayReading.aiUsage(from: nil, displayMode: .used)

        XCTAssertEqual(reading.progress ?? -1, 0.7, accuracy: 0.001)
        XCTAssertNil(noUsage.progress)
    }

    func test_display_reading_init_without_progress_is_backward_compatible() {
        let r = DisplayReading(value: nil, text: "text", unit: "", isNumeric: false, tintKey: .neutral)

        XCTAssertNil(r.progress)
    }

    func test_cpu_percent_progress_is_clamped_to_one() {
        var cpu = CPULoad()
        cpu.total = 1.5
        let snap = SystemSnapshot(cpu: cpu)
        let r = DisplayItem.system(.cpu).reading(snapshot: snap, aiUsage: nil, agent: noAgent)

        XCTAssertEqual(r.value, 150)
        XCTAssertEqual(r.progress ?? -1, 1.0, accuracy: 0.001)
    }
}
