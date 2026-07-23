import SwiftUI
import VoidNotchKit

struct RingsSkin: GaugeSkin {
    let id = "rings"

    func displayName(language: AppLanguage) -> String {
        language == .zhTW ? "圓環" : "Rings"
    }

    func makeView(items: [DisplayItem], readings: [DisplayReading]) -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                ForEach(Array(zip(items, readings).enumerated()), id: \.offset) { _, pair in
                    RingsCell(item: pair.0, reading: pair.1)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.55)))
        )
    }
}

private struct RingsCell: View {
    let item: DisplayItem
    let reading: DisplayReading

    var body: some View {
        let tint = reading.tintKey.color

        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(reading.progress == nil ? 0.08 : 0.15), lineWidth: 4)
                if let progress = reading.progress {
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if reading.isNumeric {
                    Text(reading.text + reading.unit)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text(reading.text)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: 34, height: 34)

            Text(cellLabel)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(tint.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: 30)
    }

    private var cellLabel: String {
        let lang = AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
        return (reading.label ?? item.label(language: lang)).uppercased()
    }
}
