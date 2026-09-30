import SwiftUI

/// Canvas R-Choose: two cards, Full preselected, one button. Writes the
/// choice straight to `UIMode.key`, which You > Settings can change later.
struct ModePickerView: View {
    let onContinue: () -> Void

    @AppStorage(UIMode.key) private var modeName = UIMode.full.rawValue

    private var mode: UIMode {
        return UIMode(rawValue: modeName) ?? .full
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How much do you want to see?")
                    .font(Theme.title)
                    .foregroundStyle(Theme.charcoal)
                Text("Same data, same friends. Only the amount on screen changes.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.warmGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                card(.full, symbol: "list.bullet.rectangle")
                card(.quiet, symbol: "text.alignleft")
            }
            Text("You can switch any time in You, under Settings.")
                .font(Theme.caption)
                .foregroundStyle(Theme.warmGrey)
            Spacer(minLength: 16)
            Button("Continue with \(mode.title)", action: onContinue)
                .buttonStyle(.frayedPrimary)
        }
    }

    private func card(_ option: UIMode, symbol: String) -> some View {
        let selected = option == mode
        return Button {
            modeName = option.rawValue
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.charcoal)
                    .frame(width: 34, alignment: .leading)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.charcoal)
                        if option == .full {
                            DayTypePill(text: "Most shared")
                        }
                    }
                    Text(option.blurb)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.warmGrey)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frayedCard(padding: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.charcoal : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
