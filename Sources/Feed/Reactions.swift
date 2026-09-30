import SwiftUI

/// The four preset reactions. No likes: only support (SPEC 1.4).
enum ReactionKind: String, CaseIterable, Identifiable, Codable {
    case hug, checking, same, proud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hug: return "Hug"
        case .checking: return "Checking on you"
        case .same: return "Same"
        case .proud: return "Proud of you"
        }
    }

    var symbol: String {
        switch self {
        case .hug: return "figure.2.arms.open"
        case .checking: return "bubble.left"
        case .same: return "equal.circle"
        case .proud: return "star"
        }
    }
}

/// Outlined capsule with the reaction's symbol, title and count; filled
/// apricot wash once the user has tapped it. A zero count shows no number.
struct ReactionChip: View {
    let kind: ReactionKind
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(kind.title)
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.mono(12, weight: .bold))
                }
            }
        }
        .buttonStyle(.frayedOutline(selected: selected))
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var accessibilityText: String {
        if count == 0 {
            return kind.title
        }
        return "\(kind.title), \(count)"
    }
}
