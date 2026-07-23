import SwiftUI
import VoidNotchKit

struct MenubarItemsSettingsRow: View {
    let l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(l10n.menubarItemsTitle, systemImage: "menubar.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            DisplayItemsEditor(surface: .menubar, l10n: l10n)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
