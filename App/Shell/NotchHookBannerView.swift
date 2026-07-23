//
//  NotchHookBannerView.swift
//

import SwiftUI

/// hook 接線提示列／結果列的呈現內容。與 agent alert 同一套 DynamicNotch 呈現機制，
/// 只是內容換成一列「⚡ 可接管 N 個 agent…[啟用][稍後]」或安裝結果摘要。
@MainActor
@Observable
final class NotchHookBannerState {
    enum Content {
        case prompt(
            text: String,
            primaryTitle: String, onPrimary: () -> Void,
            secondaryTitle: String, onSecondary: () -> Void)
        case info(text: String)
    }

    var content: Content?
}

/// hook 接線提示列／安裝結果列的畫面。結構比照 NotchAgentAlertView（同一個 420pt 寬卡片），
/// prompt 帶兩個按鈕，info 純文字。
struct NotchHookBannerView: View {
    let content: NotchHookBannerState.Content
    let topInset: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.yellow)
                .frame(width: 38, height: 38)
                .background(Color.yellow.opacity(0.16), in: Circle())

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if case let .prompt(_, primaryTitle, onPrimary, secondaryTitle, onSecondary) = content {
                Button(secondaryTitle, action: onSecondary)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))

                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .padding(.top, topInset)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(width: 420, alignment: .leading)
        .background(Color.yellow.opacity(0.08))
    }

    private var text: String {
        switch content {
        case let .prompt(text, _, _, _, _): return text
        case let .info(text): return text
        }
    }
}
