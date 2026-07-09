//
//  NotchComponents.swift — 通用可復用元件
//
//  面板卡片底、統計 pill、空狀態列。Token / Agent / Settings 三處共用。
//

import SwiftUI

/// 深色面板上的卡片底：半透明白填色 + 細邊框圓角。
struct NotchCardModifier: ViewModifier {
    var fillOpacity: Double = 0.055
    var border: Color = .white.opacity(0.08)
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(.white.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
    }
}

extension View {
    /// 套用 notch 面板卡片底。
    func notchCard(fillOpacity: Double = 0.055,
                   border: Color = .white.opacity(0.08),
                   cornerRadius: CGFloat = 8) -> some View
    {
        modifier(NotchCardModifier(fillOpacity: fillOpacity, border: border, cornerRadius: cornerRadius))
    }
}

/// 統計 pill：標題 + 數值。
struct SummaryPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .notchCard(fillOpacity: 0.07, cornerRadius: 6)
    }
}

/// 空狀態列：icon + 標題 + 說明。
struct NotchEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }
}
