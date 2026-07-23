import SwiftUI
import VoidNotchKit

struct GlassSkin: GaugeSkin {
    let id = "glass"

    func displayName(language: AppLanguage) -> String {
        language == .zhTW ? "玻璃" : "Glass"
    }

    func makeView(items: [DisplayItem], readings: [DisplayReading]) -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                ForEach(Array(zip(items, readings).enumerated()), id: \.offset) { _, pair in
                    GlassCell(item: pair.0, reading: pair.1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
        )
    }
}

private struct GlassCell: View {
    let item: DisplayItem
    let reading: DisplayReading

    var body: some View {
        let tint = reading.tintKey.color

        VStack(spacing: 3) {
            Text(cellLabel)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            ZStack(alignment: .bottom) {
                Text(reading.text + reading.unit)
                    .font(.system(
                        size: reading.isNumeric ? 15 : 11,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if let progress = reading.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(tint.opacity(0.18))
                            Capsule()
                                .fill(tint)
                                .frame(width: geo.size.width * CGFloat(progress))
                        }
                    }
                    .frame(width: 44, height: 3)
                }
            }
            .frame(width: 44, height: 24)
        }
        .frame(minWidth: 30)
    }

    private var cellLabel: String {
        let lang = AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
        return (reading.label ?? item.label(language: lang)).uppercased()
    }
}
