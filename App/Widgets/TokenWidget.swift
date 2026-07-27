//
//  TokenWidget.swift — AI Provider Token 用量 widget
//
//  ⚠️ Xcode app target 專屬。
//  透過 TokenStore 消費 CodexBarCore adapter，UI 不直接 import 第三方型別。
//

import Foundation
import SwiftUI
import VoidNotchKit

public struct TokenWidget: NotchWidget {
    public let id = "token"
    public let priority = 5

    let store: TokenStore
    let agentStore: AgentActivityStore

    public init(store: TokenStore, agentStore: AgentActivityStore) {
        self.store = store
        self.agentStore = agentStore
    }

    public func compactView() -> AnyView { AnyView(AISummaryCapsule(tokenStore: store, agentStore: agentStore)) }
    public func expandedView() -> AnyView { AnyView(TokenExpandedView(store: store)) }
}

struct AISummaryCapsule: View {
    let tokenStore: TokenStore
    let agentStore: AgentActivityStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: TokenStore.compactRotationInterval)) { timeline in
            let usage = tokenStore.compactDisplayUsage(at: timeline.date)
            // 優先顯示百分比；真的擠不下才退化成 icon + 狀態點。
            // 候選皆含 icon，避免只剩裸圓點；nil usage 用中性佔位。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    providerIcon(for: usage)
                    Text(compactValueText(for: usage))
                    statusDot(for: usage)
                }
                HStack(spacing: 4) {
                    providerIcon(for: usage)
                    Text(compactValueText(for: usage))
                }
                HStack(spacing: 4) {
                    providerIcon(for: usage)
                    statusDot(for: usage)
                }
            }
            .font(Theme.Fonts.compact())
            .foregroundStyle(Theme.Colors.text)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: 140, alignment: .leading)
            .help(usage?.provider.displayName ?? "Auto")
        }
    }

    @ViewBuilder
    private func providerIcon(for usage: ProviderUsage?) -> some View {
        if let provider = usage?.provider {
            ProviderGlyph(provider: provider, size: 10, weight: .semibold)
                .foregroundStyle(provider.tint)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.text)
        }
    }

    private func statusDot(for usage: ProviderUsage?) -> some View {
        Circle()
            .fill(statusColor(for: usage))
            .frame(width: 6, height: 6)
    }

    /// 有資料時用 compactText（含 %）；未登入/無資料時中性佔位，避免裸圓點。
    private func compactValueText(for usage: ProviderUsage?) -> String {
        guard let usage else { return "N/A" }
        return usage.compactText(for: tokenStore.usageDisplayMode)
    }

    private func statusColor(for usage: ProviderUsage?) -> Color {
        if tokenStore.attentionProviderCount > 0 || agentStore.attentionEventCount > 0 {
            return Theme.Colors.warning
        }
        if agentStore.activeEventCount > 0 {
            return Theme.Colors.cpu      // 活躍色(沿用 Theme 既有藍)
        }
        return usage?.status.dotColor ?? .secondary
    }
}

struct TokenExpandedView: View {
    let store: TokenStore
    @State private var selectedProvider: TokenProviderKind?
    /// Cached daily series; loaded off the body path so redraws do not re-read disk.
    @State private var dailyRecords: [TokenDailyRecord] = []
    /// Anchor date paired with `dailyRecords` (set only when reloading, not in body).
    @State private var seriesEndingAt = Date()
    /// Provider-scoped records shared by the heatmap and trend views.
    @State private var scopedDailyRecords: [TokenDailyRecord] = []
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ProviderBookmarkBar(
                providers: store.providers,
                selectedProvider: selectedUsage?.provider,
                onSelect: { selectedProvider = $0 })

            if let selectedUsage {
                TokenProviderUsageCard(
                    provider: selectedUsage,
                    displayMode: store.usageDisplayMode)
            }

            TokenContributionHeatmap(
                records: scopedDailyRecords,
                endDate: seriesEndingAt,
                scopeLabel: selectedUsage?.provider.displayName)
            TokenCostTrend(
                records: scopedDailyRecords,
                endingAt: seriesEndingAt,
                scopeLabel: selectedUsage?.provider.displayName)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 390, maxWidth: 470)
        .task {
            await reloadDailySeries()
        }
        .onChange(of: store.lastRefreshedAt) { _, _ in
            Task { await reloadDailySeries() }
        }
        // id 用「解析後」的 provider（selectedProvider 為 nil 時回退成 providers.first），
        // 否則 provider 清單晚於 daily records 抵達時 id 不變，scoped 會卡在未過濾的全 provider 聚合。
        .task(id: ScopedDailyRecordsInput(
            records: dailyRecords,
            provider: selectedUsage?.provider))
        {
            updateScopedDailyRecords()
        }
    }

    /// Loads daily series once per appear / store refresh.
    /// `TokenStore` is `@MainActor`, so the read stays on the main actor; the
    /// critical fix is that body no longer calls `dailySeries` on every redraw.
    @MainActor
    private func reloadDailySeries() async {
        let endingAt = Date()
        // Yield so the current frame can commit before the disk read.
        await Task.yield()
        let records = store.dailySeries(days: 365, endingAt: endingAt)
        dailyRecords = records
        seriesEndingAt = endingAt
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(L10n(rawValue: languageRaw).modelUsageTitle, systemImage: "chart.bar.xaxis")
                .font(.headline)

            Spacer()

            Picker(
                "Display",
                selection: Binding(
                    get: { store.usageDisplayMode },
                    set: { store.setUsageDisplayMode($0) }))
            {
                ForEach(TokenUsageDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 116)

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var selectedUsage: ProviderUsage? {
        if let selectedProvider,
           let usage = store.providers.first(where: { $0.provider == selectedProvider })
        {
            return usage
        }
        return store.providers.first
    }

    /// Updates the shared provider-scoped series outside the body path.
    private func updateScopedDailyRecords() {
        guard let selectedUsage else {
            scopedDailyRecords = dailyRecords
            return
        }
        scopedDailyRecords = dailyRecords.filter { $0.provider == selectedUsage.provider.rawValue }
    }
}

private struct ScopedDailyRecordsInput: Equatable {
    let records: [TokenDailyRecord]
    let provider: TokenProviderKind?
}

private struct HeatmapModel: Equatable {
    let costDays: [(date: String, costUsd: Double)]
    let endDate: Date
    let windowDays: Int
    let calendarGrid: [[Int]]
    let costByDate: [String: Double]
    let hasCostData: Bool

    init(records: [TokenDailyRecord], endDate: Date) {
        self.endDate = endDate
        costDays = records.compactMap { record in
            guard let costUsd = record.costUsd, costUsd > 0 else { return nil }
            return (date: record.date, costUsd: costUsd)
        }
        let earliestCostDate = costDays.map(\.date).min()
        windowDays = ContributionCalendarGrid.adaptiveWindowDays(
            earliestDate: earliestCostDate,
            endDate: tokenDateString(endDate))
        calendarGrid = ContributionCalendarGrid.build(
            days: costDays,
            endDate: tokenDateString(endDate),
            windowDays: windowDays)
        costByDate = records.reduce(into: [String: Double]()) { result, record in
            guard let costUsd = record.costUsd, costUsd > 0 else { return }
            result[record.date, default: 0] += costUsd
        }
        hasCostData = !costDays.isEmpty
    }

    static func == (lhs: HeatmapModel, rhs: HeatmapModel) -> Bool {
        lhs.windowDays == rhs.windowDays
            && lhs.endDate == rhs.endDate
            && lhs.calendarGrid == rhs.calendarGrid
            && lhs.costByDate == rhs.costByDate
            && lhs.hasCostData == rhs.hasCostData
            && lhs.costDays.count == rhs.costDays.count
            && zip(lhs.costDays, rhs.costDays).allSatisfy {
                $0.date == $1.date && $0.costUsd == $1.costUsd
            }
    }
}

private struct HeatmapModelInput: Equatable {
    let records: [TokenDailyRecord]
    let endDate: Date
}

private enum TokenWidgetDateCache {
    fileprivate static let utcGregorianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    fileprivate static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = utcGregorianCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utcGregorianCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct TrendModel: Equatable {
    let dailyCosts: [Double]
    let hasCostData: Bool
    let peakCost: Double?

    init(records: [TokenDailyRecord], endingAt: Date, selectedDays: Int) {
        let totals = records.reduce(into: [String: Double]()) { result, record in
            guard let costUsd = record.costUsd else { return }
            result[record.date, default: 0] += max(0, costUsd)
        }

        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: endingAt)
        let fullWindow: [Double] = (0..<selectedDays).compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: offset - (selectedDays - 1),
                to: endDate)
            else {
                return nil
            }
            return totals[tokenDateString(date)] ?? 0
        }

        if let firstPositive = fullWindow.firstIndex(where: { $0 > 0 }) {
            dailyCosts = Array(fullWindow[firstPositive...])
        } else {
            dailyCosts = fullWindow
        }
        hasCostData = dailyCosts.contains { $0 > 0 }
        peakCost = dailyCosts.max().flatMap { $0 > 0 ? $0 : nil }
    }
}

private struct TrendModelInput: Equatable {
    let records: [TokenDailyRecord]
    let endingAt: Date
    let selectedDays: Int
}

struct TokenContributionHeatmap: View {
    let records: [TokenDailyRecord]
    let endDate: Date
    var scopeLabel: String? = nil

    /// Measured content width; used to size the grid height before Canvas proposes a size.
    @State private var availableWidth: CGFloat = 350
    @State private var hoveredCell: HoveredCell?
    @State private var model: HeatmapModel

    init(records: [TokenDailyRecord], endDate: Date, scopeLabel: String? = nil) {
        self.records = records
        self.endDate = endDate
        self.scopeLabel = scopeLabel
        _model = State(initialValue: HeatmapModel(records: records, endDate: endDate))
    }

    private struct HoveredCell: Equatable {
        let column: Int
        let row: Int
        let date: String
        let costUsd: Double?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Activity", systemImage: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                if let scopeLabel {
                    Text(scopeLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Colors.text.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer()
                legend
                Text("\(model.windowDays)d")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.Colors.text.opacity(0.42))
                    .monospacedDigit()
            }

            if model.hasCostData && !model.calendarGrid.isEmpty {
                let columnCount = max(model.calendarGrid.count, 1)
                let metrics = Self.cellMetrics(columnCount: columnCount, availableWidth: availableWidth)
                let gridHeight = 7 * metrics.cell + 6 * metrics.gap

                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        let drawn = Self.cellMetrics(
                            columnCount: columnCount,
                            availableWidth: max(size.width, 0))
                        guard drawn.cell > 0 else { return }
                        // Left-aligned: origin at leading edge (no horizontal centering).
                        let originX: CGFloat = 0
                        let originY: CGFloat = 0

                        for columnIndex in model.calendarGrid.indices {
                            for rowIndex in model.calendarGrid[columnIndex].indices {
                                let level = model.calendarGrid[columnIndex][rowIndex]
                                guard let fill = Self.color(for: level) else { continue }

                                let cellRect = CGRect(
                                    x: originX + CGFloat(columnIndex) * (drawn.cell + drawn.gap),
                                    y: originY + CGFloat(rowIndex) * (drawn.cell + drawn.gap),
                                    width: drawn.cell,
                                    height: drawn.cell)
                                let path = Path(
                                    roundedRect: cellRect,
                                    cornerRadius: min(1.5, drawn.cell / 3),
                                    style: .continuous)
                                context.fill(path, with: .color(fill))
                            }
                        }
                    }
                    .contentShape(Rectangle())

                    if let hoveredCell {
                        let drawn = Self.cellMetrics(
                            columnCount: columnCount,
                            availableWidth: max(availableWidth, 0))
                        let anchorX = CGFloat(hoveredCell.column) * (drawn.cell + drawn.gap) + drawn.cell / 2
                        let anchorY = CGFloat(hoveredCell.row) * (drawn.cell + drawn.gap) + drawn.cell / 2
                        let tooltipWidth: CGFloat = 96
                        let tooltipX = min(
                            max(anchorX - tooltipWidth / 2, 0),
                            max(availableWidth - tooltipWidth, 0))
                        let tooltipY = anchorY >= 36
                            ? anchorY - 36
                            : anchorY + drawn.cell + 6

                        heatmapTooltip(hoveredCell)
                            .frame(width: tooltipWidth, alignment: .leading)
                            .offset(x: tooltipX, y: tooltipY)
                            .allowsHitTesting(false)
                    }
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let location):
                        let next = Self.hoveredCell(
                            at: location,
                            columnCount: columnCount,
                            availableWidth: availableWidth,
                            calendarGrid: model.calendarGrid,
                            endDate: model.endDate,
                            windowDays: model.windowDays,
                            costByDate: model.costByDate)
                        if hoveredCell != next {
                            hoveredCell = next
                        }
                    case .ended:
                        if hoveredCell != nil {
                            hoveredCell = nil
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
                .accessibilityLabel("Token activity calendar")
            } else {
                NotchEmptyState(
                    icon: "calendar.badge.clock",
                    title: "No daily activity",
                    subtitle: "Token cost history will appear after a refresh.",
                    tint: Theme.Colors.cpu)
            }
        }
        .padding(10)
        .notchCard(
            fillOpacity: 0.045,
            border: Theme.Colors.cpu.opacity(0.18),
            cornerRadius: Theme.Metrics.cornerRadius)
        .task(id: HeatmapModelInput(records: records, endDate: endDate)) {
            model = HeatmapModel(records: records, endDate: endDate)
        }
    }

    private func heatmapTooltip(_ cell: HoveredCell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.date)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
            if let costUsd = cell.costUsd {
                Text(String(format: "$%.2f", costUsd))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            } else {
                Text("No activity")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(Theme.Colors.text)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Theme.Colors.text.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Theme.Colors.text.opacity(0.22), lineWidth: 1)
        }
    }

    private static func hoveredCell(
        at location: CGPoint,
        columnCount: Int,
        availableWidth: CGFloat,
        calendarGrid: [[Int]],
        endDate: Date,
        windowDays: Int,
        costByDate: [String: Double]) -> HoveredCell?
    {
        guard location.x >= 0, location.y >= 0, availableWidth > 0 else { return nil }

        let metrics = cellMetrics(
            columnCount: columnCount,
            availableWidth: availableWidth)
        let columnStep = metrics.cell + metrics.gap
        guard columnStep > 0 else { return nil }

        let columnIndex = Int(floor(location.x / columnStep))
        let rowIndex = Int(floor(location.y / columnStep))
        guard calendarGrid.indices.contains(columnIndex),
              calendarGrid[columnIndex].indices.contains(rowIndex)
        else {
            return nil
        }

        let level = calendarGrid[columnIndex][rowIndex]
        guard level != -1 else { return nil }

        let cellRect = CGRect(
            x: CGFloat(columnIndex) * columnStep,
            y: CGFloat(rowIndex) * columnStep,
            width: metrics.cell,
            height: metrics.cell)
        let hitExpansion = min(2, metrics.gap * 0.45)
        guard cellRect.insetBy(dx: -hitExpansion, dy: -hitExpansion).contains(location),
              let date = gridDate(
                  columnIndex: columnIndex,
                  rowIndex: rowIndex,
                  endDate: endDate,
                  windowDays: windowDays)
        else {
            return nil
        }

        return HoveredCell(
            column: columnIndex,
            row: rowIndex,
            date: date,
            costUsd: costByDate[date])
    }

    private static func gridDate(
        columnIndex: Int,
        rowIndex: Int,
        endDate: Date,
        windowDays: Int) -> String?
    {
        let calendar = TokenWidgetDateCache.utcGregorianCalendar
        let formatter = TokenWidgetDateCache.utcDateFormatter
        guard let end = formatter.date(from: tokenDateString(endDate)),
              let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: end)
        else {
            return nil
        }

        let leadingDays = calendar.component(.weekday, from: cutoff) - 1
        guard let date = calendar.date(
            byAdding: .day,
            value: columnIndex * 7 + rowIndex - leadingDays,
            to: cutoff),
            date >= cutoff,
            date <= end
        else {
            return nil
        }
        return formatter.string(from: date)
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("Less")
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Self.color(for: level) ?? Theme.Colors.text.opacity(0.06))
                    .frame(width: 9, height: 9)
            }
            Text("More")
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(Theme.Colors.text.opacity(0.62))
        .accessibilityLabel("Less to more activity")
    }

    /// Fill available width from column count; cell clamped to [4, 18], gap scales with cell.
    /// If min cell would still overflow, shrink further so the grid never exceeds the container.
    private static func cellMetrics(
        columnCount: Int,
        availableWidth: CGFloat
    ) -> (cell: CGFloat, gap: CGFloat) {
        let minCell: CGFloat = 4
        let maxCell: CGFloat = 18
        // Original design used cell=7, gap=2 → keep that ratio under scaling.
        let gapRatio: CGFloat = 2.0 / 7.0
        let columns = CGFloat(max(columnCount, 1))
        let gapSlots = max(columns - 1, 0)
        // n·cell + (n−1)·(gapRatio·cell) = width  ⇒  cell = width / (n + gapRatio·(n−1))
        let denominator = columns + gapRatio * gapSlots
        guard availableWidth > 0, denominator > 0 else {
            return (minCell, minCell * gapRatio)
        }

        let fillCell = availableWidth / denominator
        var cell = min(maxCell, max(minCell, fillCell))
        // Overflow guard: prefer [4, 18], but never spill past available width.
        if cell * denominator > availableWidth {
            cell = availableWidth / denominator
        }
        return (cell, cell * gapRatio)
    }

    private static func color(for level: Int) -> Color? {
        switch level {
        case -1:
            return nil
        case 0:
            return Theme.Colors.text.opacity(0.07)
        case 1...4:
            return Theme.Colors.cpu.opacity(Theme.Chart.heatmapOpacities[level - 1])
        default:
            return Theme.Colors.text.opacity(0.07)
        }
    }
}

struct TokenCostTrend: View {
    let records: [TokenDailyRecord]
    let endingAt: Date
    var scopeLabel: String? = nil
    @State private var selectedDays = 30
    @State private var hoveredIndex: Int?
    @State private var model: TrendModel

    init(records: [TokenDailyRecord], endingAt: Date, scopeLabel: String? = nil) {
        self.records = records
        self.endingAt = endingAt
        self.scopeLabel = scopeLabel
        _model = State(initialValue: TrendModel(
            records: records,
            endingAt: endingAt,
            selectedDays: 30))
    }

    private func currencyText(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    var body: some View {
        let costs = model.dailyCosts

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Cost trend", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 11, weight: .semibold))
                if let scopeLabel {
                    Text(scopeLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Colors.text.opacity(0.62))
                        .lineLimit(1)
                }
                if let peakCost = model.peakCost {
                    Text("Peak \(currencyText(peakCost))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Colors.text.opacity(0.62))
                        .monospacedDigit()
                }
                Spacer()
                Picker("Range", selection: $selectedDays) {
                    Text("30d").tag(30)
                    Text("90d").tag(90)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 108)
            }

            if model.hasCostData {
                GeometryReader { proxy in
                    let chartSize = proxy.size
                    let plotRect = Self.plotRect(for: chartSize)
                    let maximum = model.peakCost ?? 0

                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            guard size.width > 0, size.height > 0, maximum > 0 else {
                                return
                            }

                            var line = Path()
                            for index in costs.indices {
                                let point = Self.point(
                                    at: index,
                                    costs: costs,
                                    plotRect: plotRect,
                                    maximum: maximum)
                                if index == 0 {
                                    line.move(to: point)
                                } else {
                                    line.addLine(to: point)
                                }
                            }

                            var area = line
                            if !costs.isEmpty {
                                let firstPoint = Self.point(
                                    at: 0,
                                    costs: costs,
                                    plotRect: plotRect,
                                    maximum: maximum)
                                let lastPoint = Self.point(
                                    at: costs.count - 1,
                                    costs: costs,
                                    plotRect: plotRect,
                                    maximum: maximum)
                                area.addLine(to: CGPoint(x: lastPoint.x, y: plotRect.maxY))
                                area.addLine(to: CGPoint(x: firstPoint.x, y: plotRect.maxY))
                                area.closeSubpath()
                            }

                            var peakGuide = Path()
                            peakGuide.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
                            peakGuide.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.minY))

                            var baseline = Path()
                            baseline.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
                            baseline.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))

                            context.fill(area, with: .color(Theme.Colors.cpu.opacity(0.12)))
                            context.stroke(
                                peakGuide,
                                with: .color(Theme.Colors.text.opacity(0.10)),
                                lineWidth: 1)
                            context.stroke(
                                baseline,
                                with: .color(Theme.Colors.text.opacity(0.12)),
                                lineWidth: 1)

                            context.stroke(
                                line,
                                with: .color(Theme.Colors.cpu),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        }
                        .contentShape(Rectangle())

                        if let hoveredIndex, costs.indices.contains(hoveredIndex) {
                            Canvas { context, size in
                                guard size.width > 0, size.height > 0 else { return }
                                let point = Self.point(
                                    at: hoveredIndex,
                                    costs: costs,
                                    plotRect: plotRect,
                                    maximum: maximum)
                                var crosshair = Path()
                                crosshair.move(to: CGPoint(x: point.x, y: plotRect.minY))
                                crosshair.addLine(to: CGPoint(x: point.x, y: plotRect.maxY))
                                context.stroke(
                                    crosshair,
                                    with: .color(Theme.Colors.text.opacity(0.26)),
                                    lineWidth: 1)
                            }
                            .allowsHitTesting(false)
                        }

                        if let hoveredIndex, costs.indices.contains(hoveredIndex) {
                            let point = Self.point(
                                at: hoveredIndex,
                                costs: costs,
                                plotRect: plotRect,
                                maximum: maximum)
                            let tooltipWidth: CGFloat = 112
                            let tooltipX = min(
                                max(point.x - tooltipWidth / 2, 0),
                                max(chartSize.width - tooltipWidth, 0))

                            trendTooltip(
                                date: tokenDateString(
                                    offsetDays: hoveredIndex - (costs.count - 1),
                                    from: endingAt),
                                costUsd: costs[hoveredIndex])
                                .frame(width: tooltipWidth, alignment: .leading)
                                .offset(x: tooltipX, y: 4)
                                .allowsHitTesting(false)
                        }
                    }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            let next = Self.nearestIndex(
                                at: location,
                                plotRect: plotRect,
                                count: costs.count)
                            if hoveredIndex != next {
                                hoveredIndex = next
                            }
                        case .ended:
                            if hoveredIndex != nil {
                                hoveredIndex = nil
                            }
                        }
                    }
                }
                .frame(height: 76)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Token cost trend for the last \(selectedDays) days")

                HStack {
                    // Labels track the actual plotted span (after leading-zero clip).
                    Text(tokenDateString(offsetDays: -(max(costs.count, 1) - 1), from: endingAt))
                    Spacer()
                    Text(tokenDateString(endingAt))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Colors.text.opacity(0.55))
            } else {
                NotchEmptyState(
                    icon: "chart.xyaxis.line",
                    title: "No cost history",
                    subtitle: "Daily costs will appear after a refresh.",
                    tint: Theme.Colors.cpu)
            }
        }
        .padding(10)
        .notchCard(
            fillOpacity: 0.045,
            border: Theme.Colors.cpu.opacity(0.18),
            cornerRadius: Theme.Metrics.cornerRadius)
        .task(id: TrendModelInput(
            records: records,
            endingAt: endingAt,
            selectedDays: selectedDays))
        {
            model = TrendModel(
                records: records,
                endingAt: endingAt,
                selectedDays: selectedDays)
        }
    }

    private func trendTooltip(date: String, costUsd: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
            Text(currencyText(costUsd))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(Theme.Colors.text)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Theme.Colors.text.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Theme.Colors.text.opacity(0.22), lineWidth: 1)
        }
    }

    private static func plotRect(for size: CGSize) -> CGRect {
        let inset: CGFloat = 4
        return CGRect(
            x: inset,
            y: inset,
            width: max(size.width - inset * 2, 0),
            height: max(size.height - inset * 2, 0))
    }

    private static func point(
        at index: Int,
        costs: [Double],
        plotRect: CGRect,
        maximum: Double) -> CGPoint
    {
        let xStep = costs.count > 1
            ? plotRect.width / CGFloat(costs.count - 1)
            : 0
        let cost = costs[index]
        return CGPoint(
            x: plotRect.minX + CGFloat(index) * xStep,
            y: plotRect.maxY - CGFloat(cost / maximum) * plotRect.height)
    }

    private static func nearestIndex(
        at location: CGPoint,
        plotRect: CGRect,
        count: Int) -> Int?
    {
        guard count > 0 else { return nil }
        guard plotRect.width > 0, plotRect.height > 0 else { return nil }

        let x = min(max(location.x, plotRect.minX), plotRect.maxX)
        guard count > 1 else { return 0 }

        let xStep = plotRect.width / CGFloat(count - 1)
        guard xStep > 0 else { return 0 }
        return min(
            max(Int(((x - plotRect.minX) / xStep).rounded()), 0),
            count - 1)
    }
}

private func tokenDateString(_ date: Date) -> String {
    TokenDailyMerge.normalizedDateString(date, calendar: .current)
}

private func tokenDateString(offsetDays: Int, from date: Date) -> String {
    let calendar = Calendar.current
    guard let offsetDate = calendar.date(byAdding: .day, value: offsetDays, to: date) else {
        return tokenDateString(date)
    }
    return tokenDateString(offsetDate)
}

private struct ProviderBookmarkBar: View {
    let providers: [ProviderUsage]
    let selectedProvider: TokenProviderKind?
    let onSelect: (TokenProviderKind) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(providers) { usage in
                ProviderBookmarkButton(
                    usage: usage,
                    isSelected: selectedProvider == usage.provider,
                    onSelect: { onSelect(usage.provider) })
            }
        }
        .frame(height: 22)
    }
}

private struct ProviderBookmarkButton: View {
    let usage: ProviderUsage
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                ProviderGlyph(provider: usage.provider, size: 10, weight: .semibold)
                Text(usage.provider.shortDisplayName)
                    .lineLimit(1)
                Circle()
                    .fill(usage.status.dotColor)
                    .frame(width: 5, height: 5)
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? usage.provider.tint : .white.opacity(0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? usage.provider.tint.opacity(0.45) : .white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(usage.provider.displayName)
    }

    private var background: some ShapeStyle {
        isSelected ? usage.provider.tint.opacity(0.18) : .white.opacity(0.06)
    }
}

private struct TokenProviderUsageCard: View {
    let provider: ProviderUsage
    let displayMode: TokenUsageDisplayMode
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let sortedWindows = provider.sortedUsageWindows
        let l10n = L10n(rawValue: languageRaw)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ProviderIcon(provider: provider.provider, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        ProviderStatusBadge(status: provider.status)
                    }

                    Text(provider.sourceSummaryText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(provider.primaryMetricText(for: displayMode))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(provider.updatedText ?? l10n.notRefreshed)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !sortedWindows.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sortedWindows) { window in
                        UsageWindowRow(
                            window: window,
                            provider: provider.provider,
                            displayMode: displayMode)
                    }
                }
            }

            if provider.hasTokenOrCostData {
                TokenCostSummary(provider: provider)
            } else if sortedWindows.isEmpty {
                NotchEmptyState(
                    icon: "tray",
                    title: provider.status == .unsupported ? l10n.adapterPending : l10n.noUsageWindow,
                    subtitle: provider.providerActionHint,
                    tint: provider.status.statusColor)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: provider.status == .available ? "checkmark.seal" : "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(provider.status.statusColor)
                    .frame(width: 14)
                Text(provider.statusDetailText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .notchCard(
            fillOpacity: provider.status == .available ? 0.075 : 0.045,
            border: provider.status.borderColor,
            cornerRadius: Theme.Metrics.cornerRadius)
    }
}

private struct TokenCostSummary: View {
    let provider: ProviderUsage

    var body: some View {
        HStack(spacing: 10) {
            metric(title: "Session", value: provider.sessionTokensText)
            metric(title: "30d", value: provider.last30DaysTokensText)
            metric(title: "Session cost", value: provider.sessionCostText)
            metric(title: "30d cost", value: provider.last30DaysCostText)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// provider 圖示/色票與狀態色 → App/Theme/ProviderAppearance.swift（單一真相）
