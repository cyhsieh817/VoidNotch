//
//  ProviderComponents.swift — provider 相關可復用元件
//
//  單一真相：TokenWidget（notch 面板）與 ProviderSettingsView（設定視窗）
//  先前各自實作 icon / 狀態徽章，此處合併；視覺對應見 ProviderAppearance.swift。
//

import AppKit
import SwiftUI
import VoidNotchKit

/// Provider 顯示 glyph。每個 provider 以自己的 AppStorage key 即時觀察並持久化外觀。
/// 內層以 provider.rawValue 為 id 的 storage-backed view，避免 provider 輪替時沿用前一個 key。
struct ProviderGlyph: View {
    let provider: TokenProviderKind
    let size: CGFloat
    let weight: Font.Weight

    init(provider: TokenProviderKind, size: CGFloat, weight: Font.Weight) {
        self.provider = provider
        self.size = size
        self.weight = weight
    }

    var body: some View {
        ProviderGlyphStorage(provider: provider, size: size, weight: weight)
            .id(provider.rawValue)
    }
}

/// 綁定單一 provider 的 icon 偏好；僅由 ProviderGlyph 建立，隨 .id 重建。
private struct ProviderGlyphStorage: View {
    let provider: TokenProviderKind
    let size: CGFloat
    let weight: Font.Weight
    @AppStorage private var choiceRawValue: String

    init(provider: TokenProviderKind, size: CGFloat, weight: Font.Weight) {
        self.provider = provider
        self.size = size
        self.weight = weight
        _choiceRawValue = AppStorage(
            wrappedValue: ProviderIconChoice.default.rawValue,
            ProviderIconChoice.preferenceKey(for: provider))
    }

    var body: some View {
        ProviderGlyphArtwork(
            provider: provider,
            choice: ProviderIconChoice(rawValue: choiceRawValue) ?? .default,
            size: size,
            weight: weight)
    }
}

/// 固定 choice 的 glyph artwork，供設定選項預覽；實際 provider 顯示一律使用 ProviderGlyph。
struct ProviderGlyphArtwork: View {
    let provider: TokenProviderKind
    let choice: ProviderIconChoice
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        Group {
            if let image = resourceImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: provider.iconSystemName)
                    .font(.system(size: size, weight: weight))
                    .frame(height: size)
            }
        }
    }

    private var resourceImage: NSImage? {
        guard let resourceName = choice.resourceName,
              let url = Bundle.main.url(
                  forResource: resourceName,
                  withExtension: "svg",
                  subdirectory: "provider-icons"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}

/// 圓角色塊 + provider SF Symbol。size 決定整體尺寸，字級與圓角按比例縮放。
struct ProviderIcon: View {
    let provider: TokenProviderKind
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(provider.tint.opacity(0.18))
            ProviderGlyph(provider: provider, size: size * 0.47, weight: .semibold)
                .foregroundStyle(provider.tint)
        }
        .frame(width: size, height: size)
    }
}

/// 狀態圓點。
struct ProviderStatusDot: View {
    let status: ProviderUsageStatus
    var size: CGFloat = 5

    var body: some View {
        Circle()
            .fill(status.dotColor)
            .frame(width: size, height: size)
    }
}

/// 狀態徽章：圓點 + 狀態文字的膠囊。
struct ProviderStatusBadge: View {
    let status: ProviderUsageStatus

    var body: some View {
        HStack(spacing: 4) {
            ProviderStatusDot(status: status)
            Text(status.label)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(status.statusColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.statusColor.opacity(0.12), in: Capsule())
    }
}

/// 配額視窗列：標題 + 種類膠囊 + 指標 + 進度條 + 剩餘/已用/重置。
/// notch 面板與設定視窗共用；先前兩處各持一份僅字級差 1pt 的複本。
struct UsageWindowRow: View {
    let window: ProviderUsageWindow
    let provider: TokenProviderKind
    let displayMode: TokenUsageDisplayMode
    @AppStorage(AppLanguage.preferenceKey) private var languageRaw = AppLanguage.default.rawValue

    var body: some View {
        let l10n = L10n(rawValue: languageRaw)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(window.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Text(window.kind.displayName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())

                Spacer(minLength: 8)

                Text(window.usageKnown ? window.metricText(for: displayMode) : l10n.waiting)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(window.usageKnown ? barColor : .secondary)
            }

            UsageBar(percent: window.usageKnown ? window.percent(for: displayMode) : 0, color: barColor)

            HStack(spacing: 8) {
                Text(l10n.leftPercent(window.remainingPercent))
                Text(l10n.usedPercent(window.usedPercent))
                Spacer(minLength: 8)
                if let resetText = window.resetText {
                    Text(resetText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                        .layoutPriority(1)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var barColor: Color {
        guard window.usageKnown else { return .secondary }
        if window.remainingPercent <= 20 {
            return .orange
        }
        return provider.tint
    }
}

/// 膠囊進度條。
struct UsageBar: View {
    let percent: Int
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.10))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
        .frame(height: height)
    }
}
