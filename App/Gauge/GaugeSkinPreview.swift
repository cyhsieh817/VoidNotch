import SwiftUI
import VoidNotchKit

/// 設定頁外觀選擇：一排真身預覽卡（各 skin 以固定樣本資料渲染縮小版）。
struct GaugeSkinPicker: View {
    @Binding var skinID: String
    let language: AppLanguage

    private static let sampleItems: [DisplayItem] = [.system(.cpu), .aiUsage]
    private static let sampleReadings: [DisplayReading] = [
        DisplayReading(value: 42, text: "42", unit: "%", isNumeric: true, tintKey: .cpu, progress: 0.42),
        DisplayReading(value: nil, text: "45%", unit: "", isNumeric: false, tintKey: .ai, label: "Claude", progress: 0.45),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(GaugeSkinRegistry.shared.all, id: \.id) { skin in
                    SkinPreviewCard(
                        skin: skin,
                        language: language,
                        isSelected: skinID == skin.id,
                        onTap: { skinID = skin.id }
                    )
                }
            }
        }
    }

    /// 單一 skin 預覽卡：真身縮小渲染 + 選中高亮。
    private struct SkinPreviewCard: View {
        let skin: GaugeSkin
        let language: AppLanguage
        let isSelected: Bool
        let onTap: () -> Void

        var body: some View {
            VStack(spacing: 6) {
                // 預覽區：真身縮小；深色墊底讓透明／毛玻璃 skin 可見
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))
                    skin.makeView(
                        items: GaugeSkinPicker.sampleItems,
                        readings: GaugeSkinPicker.sampleReadings
                    )
                        .frame(width: 158, height: 64)
                        .scaleEffect(0.62, anchor: .center)
                        .frame(width: 104, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(width: 104, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(skin.displayName(language: language))
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.accentColor : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
    }
}
