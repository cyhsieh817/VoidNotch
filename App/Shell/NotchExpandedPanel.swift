//
//  NotchExpandedPanel.swift
//

import SwiftUI
import VoidNotchKit

/// 展開面板（分頁版）。還原 docs/demo/index.html 的儀表板：頂部書籤分頁
/// （系統監控／模型配額／Agent 活動），一次只顯示一張 widget 的展開視圖。
/// 三 widget 直疊會把面板撐到溢出螢幕（頂端被劉海吃掉、底端被 Dock 裁掉且捲不到），
/// 分頁讓每張內容都短到完整可見，不再需要長捲動。
struct NotchExpandedPanel: View {
    let registry: WidgetRegistry
    /// DynamicNotchKit 已保留實體劉海高度，這裡只補一個視覺餘量（見 NotchMetrics.expandedTopInset）。
    let topInset: CGFloat
    /// 可捲區高度上限，依「半螢幕視窗」天花板計算（見 NotchMetrics.expandedScrollMaxHeight）。
    let scrollMaxHeight: CGFloat

    /// 面板固定寬，貼齊 demo 的 440pt 卡片。
    private let panelWidth: CGFloat = 440

    @State private var selectedID: String?
    @Namespace private var tabPillNamespace
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    private var l10n: L10n { L10n(rawValue: languageRaw) }

    private var widgets: [any NotchWidget] {
        registry.visibleSortedByPriority
    }

    private var leadingWidgets: [any NotchWidget] {
        _ = registry.layout.revision
        return registry.widgets(on: .leading)
    }

    private var trailingWidgets: [any NotchWidget] {
        _ = registry.layout.revision
        return registry.widgets(on: .trailing)
    }

    private var activeWidget: (any NotchWidget)? {
        if let selectedID, let match = widgets.first(where: { $0.id == selectedID }) {
            return match
        }
        return widgets.first
    }

    var body: some View {
        // DynamicNotchKit 把展開視窗寫死成半螢幕高（見 NotchMetrics.expandedScrollMaxHeight），是硬天花板。
        // ScrollView 以 maxHeight 封頂：短內容貼合自然高度，長內容在半螢幕視窗內自捲；
        // 頂端錨點列與分頁列永遠穩定可見，不再被推出畫面。
        VStack(spacing: 10) {
            notchHeader
            if widgets.count > 1 {
                tabBar
            }

            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    if let activeWidget {
                        activeWidget.expandedView()
                            .id(activeWidget.id)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
            }
            // DynamicNotchKit 外層 safeAreaInset 會變成 ScrollView 的垂直 content margin；面板已靠 topInset 避讓瀏海，此處只歸零 scroll-content 邊距。
            .contentMargins(.vertical, 0, for: .scrollContent)
            .frame(maxHeight: scrollMaxHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, topInset)
        .padding(.horizontal, 16)
        .padding(.bottom, NotchMetrics.expandedBottomMargin)
        .frame(width: panelWidth)
    }

    /// 頂部錨點：重現實體瀏海兩側的 compact 資訊（左＝系統指標，右＝AI 摘要），中央留白讓出劉海位置。
    /// 給面板一個固定置頂的實體物件，內容不再貼著螢幕頂往上鑽。
    private var notchHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(leadingWidgets, id: \.id) { widget in
                    widget.compactView()
                }
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                ForEach(trailingWidgets, id: \.id) { widget in
                    widget.compactView()
                }
            }
        }
        .font(Theme.Fonts.compact())
        .foregroundStyle(Theme.Colors.text)
        .frame(maxWidth: .infinity)
        .frame(height: max(20, registry.layout.contentHeight + 4))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(widgets, id: \.id) { widget in
                tabButton(widget)
            }
        }
        .padding(3)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func tabButton(_ widget: any NotchWidget) -> some View {
        let isActive = activeWidget?.id == widget.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedID = widget.id
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: widget.settingsIconSystemName)
                    .font(.system(size: 11, weight: .semibold))
                Text(tabTitle(for: widget))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "tabPill", in: tabPillNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tabTitle(for: widget))
    }

    /// 分頁標題（依語言偏好）。未知 widget 退回 settingsTitle。
    private func tabTitle(for widget: any NotchWidget) -> String {
        switch widget.id {
        case "system": return l10n.tabSystem
        case "token": return l10n.tabToken
        case "agent-activity": return l10n.tabAgent
        case "launchd-schedule": return l10n.tabScheduled
        default: return widget.settingsTitle
        }
    }
}
