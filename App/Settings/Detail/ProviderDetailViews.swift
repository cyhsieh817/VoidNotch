import SwiftUI
import VoidNotchKit
import Foundation

struct ProviderSidebarRow: View {
    let provider: TokenProviderKind
    let usage: ProviderUsage
    let isSelected: Bool
    let isEnabled: Bool
    let canDisable: Bool
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    ProviderIcon(provider: provider, size: 26)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            ProviderStatusDot(status: usage.status)
                        }

                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in onToggle(newValue) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!canDisable)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
        }
    }

    private var subtitle: String {
        if usage.status == .available {
            return "\(provider.capabilitySummary) · \(usage.dataCoverageText)"
        }
        return "\(usage.status.label) · \(provider.capabilitySummary)"
    }
}

struct ProviderDetailHeader: View {
    let provider: TokenProviderKind
    let usage: ProviderUsage
    let isEnabled: Bool
    let canDisable: Bool
    let onRefresh: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ProviderIcon(provider: provider, size: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(provider.displayName)
                        .font(.system(size: 22, weight: .bold))
                    ProviderStatusBadge(status: usage.status)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(usage.status == .refreshing)

            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in onToggle(newValue) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!canDisable)
        }
    }

    private var subtitle: String {
        var parts = [usage.sourceSummaryText]
        if usage.versionText != "-" {
            parts.append(usage.versionText)
        }
        if let updatedText = usage.updatedText {
            parts.append(updatedText)
        }
        return parts.joined(separator: " · ")
    }
}

struct ProviderStateBanner: View {
    let usage: ProviderUsage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(usage.status.statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(usage.providerActionHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(usage.status.statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(usage.status.statusColor.opacity(0.18), lineWidth: 1)
        }
    }

    private var title: String {
        switch usage.status {
        case .available:
            return "Provider data is available"
        case .refreshing:
            return "Refreshing provider data"
        case .unsupported:
            return "Adapter is pending"
        case .unavailable:
            return "No provider data yet"
        case .idle:
            return "Waiting for first refresh"
        }
    }

    private var icon: String {
        switch usage.status {
        case .available:
            return "checkmark.seal"
        case .refreshing:
            return "arrow.clockwise"
        case .unsupported:
            return "hammer"
        case .unavailable:
            return "exclamationmark.triangle"
        case .idle:
            return "clock"
        }
    }
}

struct ProviderCapabilityMatrix: View {
    let provider: TokenProviderKind
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capabilities")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 8) {
                capability("Live", enabled: provider.supportsLiveUsageSnapshot)
                capability("Cost", enabled: provider.supportsCostSnapshot)
                capability("Quota", enabled: provider.supportsQuotaSnapshot)
                capability("Data", enabled: usage.hasAnyUsageData)
            }

            Text(provider.expectedDataText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func capability(_ title: String, enabled: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? provider.tint : .secondary)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background((enabled ? provider.tint.opacity(0.13) : Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct ProviderInfoGrid: View {
    let usage: ProviderUsage

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            infoRow("State", usage.status.label)
            infoRow("Source", usage.sourceText)
            infoRow("Strategy", usage.strategyID ?? "-")
            infoRow("Version", usage.versionText)
            infoRow("Updated", usage.updatedText ?? "-")
            infoRow("Account", usage.accountText)
            infoRow("Plan", usage.planText)
            infoRow("Coverage", usage.dataCoverageText)
        }
        .font(.system(size: 12))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }
}

struct ProviderUsageDetail: View {
    let usage: ProviderUsage
    let displayMode: TokenUsageDisplayMode

    var body: some View {
        let sortedWindows = usage.sortedUsageWindows

        VStack(alignment: .leading, spacing: 10) {
            Text("Usage")
                .font(.system(size: 14, weight: .semibold))

            if !sortedWindows.isEmpty {
                VStack(spacing: 9) {
                    ForEach(sortedWindows) { window in
                        UsageWindowRow(
                            window: window,
                            provider: usage.provider,
                            displayMode: displayMode)
                    }
                }
            } else {
                NotchEmptyState(
                    icon: "tray",
                    title: "No session or quota window returned.",
                    subtitle: usage.providerActionHint,
                    tint: usage.status.statusColor)
            }

            if usage.hasTokenOrCostData {
                Divider().padding(.vertical, 2)
                ProviderCostDetail(usage: usage)
            }
        }
    }
}

struct ProviderCostDetail: View {
    let usage: ProviderUsage

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            row("Session tokens", usage.sessionTokensText)
            row("Last 30 days", usage.last30DaysTokensText)
            row("Session cost", usage.sessionCostText)
            row("30d cost", usage.last30DaysCostText)
        }
        .font(.system(size: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .monospacedDigit()
        }
    }
}

private enum ProviderUsageRange: Int, CaseIterable, Identifiable {
    case days30 = 30
    case days90 = 90
    case days180 = 180
    case days365 = 365

    var id: Int { rawValue }

    var title: String { "\(rawValue)d" }
}

struct ProviderDailyUsageDetail: View {
    let store: TokenStore
    let provider: TokenProviderKind

    @State private var selectedRange: ProviderUsageRange = .days90
    @State private var dailyRecords: [TokenDailyRecord] = []
    @State private var seriesEndingAt = Date()
    @State private var isLoading = false

    private var summary: TokenUsageStats.Summary {
        TokenUsageStats.summary(records: dailyRecords)
    }

    private var dailyRows: [TokenUsageStats.DailyRow] {
        TokenUsageStats.dailyRows(records: dailyRecords)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if dailyRecords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ProviderUsageSummaryCard(summary: summary, range: selectedRange)
                    NotchEmptyState(
                        icon: isLoading ? "arrow.clockwise" : "chart.bar.xaxis",
                        title: isLoading ? "Loading daily usage" : "No daily usage history",
                        subtitle: isLoading
                            ? "Reading the selected usage window."
                            : "Daily cost and token history will appear after a provider refresh.",
                        tint: Theme.Colors.cpu)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ProviderUsageSummaryCard(summary: summary, range: selectedRange)
                        .frame(width: 236)
                    ProviderUsageLargeHeatmap(
                        records: dailyRecords,
                        endingAt: seriesEndingAt,
                        windowDays: selectedRange.rawValue)
                        .frame(maxWidth: .infinity)
                }

                // 裸用：TokenCostTrend 自身已套 .padding(10) + .notchCard，
                // 再包一層會疊出雙重邊框與雙倍留白。
                TokenCostTrend(records: dailyRecords, endingAt: seriesEndingAt)

                ProviderDailyRowsSection(
                    rows: dailyRows,
                    providerName: provider.displayName,
                    rangeDays: selectedRange.rawValue)
            }
        }
        .task {
            await reloadDailySeries()
        }
        .onChange(of: selectedRange) { _, _ in
            Task { await reloadDailySeries() }
        }
        .onChange(of: provider) { _, _ in
            Task { await reloadDailySeries() }
        }
        .onChange(of: store.lastRefreshedAt) { _, _ in
            Task { await reloadDailySeries() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                ProviderIcon(provider: provider, size: 18)
                Text(provider.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text("daily usage")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.text.opacity(0.58))
            }

            Spacer()

            Text("Range")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.text.opacity(0.62))

            Picker("Usage range", selection: $selectedRange) {
                ForEach(ProviderUsageRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @MainActor
    private func reloadDailySeries() async {
        isLoading = true
        let endingAt = Date()
        await Task.yield()
        dailyRecords = store.dailySeries(
            days: selectedRange.rawValue,
            endingAt: endingAt,
            provider: provider)
        seriesEndingAt = endingAt
        isLoading = false
    }
}

private struct ProviderUsageSummaryCard: View {
    let summary: TokenUsageStats.Summary
    let range: ProviderUsageRange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Summary")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Last \(range.rawValue) days")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Colors.text.opacity(0.52))
                    .monospacedDigit()
            }

            if summary.earliestDate == nil {
                NotchEmptyState(
                    icon: "chart.bar.xaxis",
                    title: "No summary yet",
                    subtitle: "There is no daily usage data in this range.",
                    tint: Theme.Colors.cpu)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                    metricRow("Total cost", currencyText(summary.totalCost))
                    metricRow("Total tokens", compactTokenText(summary.totalTokens))
                        .help("Exact total: \(summary.totalTokens.formatted()) tokens")
                    metricRow("Active days", "\(summary.activeDays)")
                    metricRow("Daily average", currencyText(summary.dailyAverageCost))
                    metricRow(peakDayTitle, peakDayValue)
                        .help(peakDayText)
                }
                .font(.system(size: 12))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard(border: Theme.Colors.text.opacity(0.10))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Date moves into the tile title so the value stays a single legible number.
    /// Packing "2026-07-20 · $637.18" into one narrow tile scaled it down to unreadable.
    private var peakDayTitle: String {
        guard let peakDay = summary.peakDay else { return "Peak day" }
        return "Peak \(String(peakDay.date.suffix(5)))"
    }

    private var peakDayValue: String {
        guard let peakDay = summary.peakDay else { return "-" }
        return currencyText(peakDay.cost)
    }

    private var peakDayText: String {
        guard let peakDay = summary.peakDay else { return "-" }
        return "\(peakDay.date) · \(currencyText(peakDay.cost))"
    }
}

private struct ProviderUsageLargeHeatmap: View {
    let records: [TokenDailyRecord]
    let endingAt: Date
    let windowDays: Int

    @State private var availableWidth: CGFloat = 600

    private var costDays: [(date: String, costUsd: Double)] {
        records.compactMap { record in
            guard let costUsd = record.costUsd, costUsd > 0 else { return nil }
            return (record.date, costUsd)
        }
    }

    private var calendarGrid: [[Int]] {
        ContributionCalendarGrid.build(
            days: costDays,
            endDate: providerUsageDateString(endingAt),
            windowDays: windowDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label("Extended activity", systemImage: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(windowDays)d")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Colors.text.opacity(0.52))
                    .monospacedDigit()
            }

            if costDays.isEmpty || calendarGrid.isEmpty {
                NotchEmptyState(
                    icon: "calendar.badge.clock",
                    title: "No daily activity",
                    subtitle: "A larger cost heatmap will appear after a provider refresh.",
                    tint: Theme.Colors.cpu)
            } else {
                let columnCount = max(calendarGrid.count, 1)
                let metrics = Self.cellMetrics(columnCount: columnCount, availableWidth: availableWidth)
                let gridHeight = 7 * metrics.cell + 6 * metrics.gap

                Canvas { context, size in
                    let drawn = Self.cellMetrics(
                        columnCount: columnCount,
                        availableWidth: max(size.width, 0))
                    guard drawn.cell > 0 else { return }

                    for columnIndex in calendarGrid.indices {
                        for rowIndex in calendarGrid[columnIndex].indices {
                            let level = calendarGrid[columnIndex][rowIndex]
                            guard let fill = Self.color(for: level) else { continue }
                            let cellRect = CGRect(
                                x: CGFloat(columnIndex) * (drawn.cell + drawn.gap),
                                y: CGFloat(rowIndex) * (drawn.cell + drawn.gap),
                                width: drawn.cell,
                                height: drawn.cell)
                            context.fill(
                                Path(
                                    roundedRect: cellRect,
                                    cornerRadius: min(2.5, drawn.cell / 3),
                                    style: .continuous),
                                with: .color(fill))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: gridHeight)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { availableWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, newWidth in
                                availableWidth = newWidth
                            }
                    })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Extended token activity calendar for the last \(windowDays) days")

                HStack {
                    Text(providerUsageDateString(offsetDays: -(windowDays - 1), from: endingAt))
                    Spacer()
                    Text(providerUsageDateString(endingAt))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Colors.text.opacity(0.55))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard(border: Theme.Colors.cpu.opacity(0.18))
    }

    private static func cellMetrics(
        columnCount: Int,
        availableWidth: CGFloat
    ) -> (cell: CGFloat, gap: CGFloat) {
        let columns = CGFloat(max(columnCount, 1))
        let gapRatio: CGFloat = 2.0 / 7.0
        let denominator = columns + gapRatio * max(columns - 1, 0)
        guard availableWidth > 0, denominator > 0 else { return (7, 2) }
        let cell = min(11, max(6, availableWidth / denominator))
        return (min(cell, availableWidth / denominator), cell * gapRatio)
    }

    private static func color(for level: Int) -> Color? {
        switch level {
        case -1: return nil
        case 0: return Theme.Colors.text.opacity(0.07)
        case 1: return Theme.Colors.cpu.opacity(0.22)
        case 2: return Theme.Colors.cpu.opacity(0.40)
        case 3: return Theme.Colors.cpu.opacity(0.62)
        case 4: return Theme.Colors.cpu.opacity(0.86)
        default: return Theme.Colors.text.opacity(0.07)
        }
    }
}

private struct ProviderDailyRowsSection: View {
    let rows: [TokenUsageStats.DailyRow]
    let providerName: String
    let rangeDays: Int

    @State private var isPresentingSheet = false

    var body: some View {
        Button {
            isPresentingSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text.opacity(0.58))
                Text("Daily details")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(rows.count) rows")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Colors.text.opacity(0.52))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text.opacity(0.58))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(rows.isEmpty)
        .opacity(rows.isEmpty ? 0.5 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard(fillOpacity: 0.035, border: Theme.Colors.text.opacity(0.10), cornerRadius: 6)
        .sheet(isPresented: $isPresentingSheet) {
            ProviderDailyRowsSheet(
                rows: rows,
                providerName: providerName,
                rangeDays: rangeDays)
        }
    }
}

private struct ProviderDailyRowsSheet: View {
    let rows: [TokenUsageStats.DailyRow]
    let providerName: String
    let rangeDays: Int

    @Environment(\.dismiss) private var dismiss

    private let tokensWidth: CGFloat = 92
    private let costWidth: CGFloat = 82

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(providerName) · daily details")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Last \(rangeDays) days · \(rows.count) rows")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.text.opacity(0.58))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 16)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    dailyRow(
                        date: "Date",
                        tokens: "Tokens",
                        cost: "Cost",
                        isHeader: true)
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        dailyRow(
                            date: row.date,
                            tokens: row.tokens.formatted(),
                            cost: currencyText(row.costUsd),
                            isHeader: false)
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxHeight: .infinity)

            Divider()
                .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 560, height: 480)
    }

    private func dailyRow(
        date: String,
        tokens: String,
        cost: String,
        isHeader: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(date)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(tokens)
                .frame(width: tokensWidth, alignment: .trailing)
            Text(cost)
                .frame(width: costWidth, alignment: .trailing)
        }
        .font(.system(size: isHeader ? 10 : 11, weight: isHeader ? .semibold : .regular, design: .monospaced))
        .foregroundStyle(Theme.Colors.text.opacity(isHeader ? 0.62 : 0.88))
        .frame(minHeight: 28)
    }
}

private func currencyText(_ amount: Double) -> String {
    String(format: "$%.2f", amount)
}

private func compactTokenText(_ tokens: Int) -> String {
    let value = Double(tokens)
    let magnitude = abs(value)
    let unit: (divisor: Double, suffix: String)? = switch magnitude {
    case 1_000_000_000...: (1_000_000_000, "B")
    case 1_000_000...: (1_000_000, "M")
    case 1_000...: (1_000, "K")
    default: nil
    }

    guard let unit else { return tokens.formatted() }

    let number = String(format: "%.2f", value / unit.divisor)
        .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    return "\(number)\(unit.suffix)"
}

private func providerUsageDateString(_ date: Date) -> String {
    TokenDailyMerge.normalizedDateString(date, calendar: .current)
}

private func providerUsageDateString(offsetDays: Int, from date: Date) -> String {
    let calendar = Calendar.current
    guard let offsetDate = calendar.date(byAdding: .day, value: offsetDays, to: date) else {
        return providerUsageDateString(date)
    }
    return providerUsageDateString(offsetDate)
}
