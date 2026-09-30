import SwiftUI

/// The five badges, two per row. Earned ones read in charcoal with their
/// level; locked ones show how to earn them. Tapping opens the rule.
struct TrophiesSection: View {
    let ledgers: [DayLedger]
    let engine: TrophyEngine

    @State private var selected: TrophyDetail?

    private struct Entry: Identifiable {
        let badge: Badge
        let detail: TrophyDetail

        var id: String {
            return detail.id
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var entries: [Entry] {
        let details = engine.badgeDetails(ledgers)
        return zip(Badge.allCases, details).map { Entry(badge: $0, detail: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Trophies")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(entries) { entry in
                    Button {
                        selected = entry.detail
                    } label: {
                        cell(badge: entry.badge, detail: entry.detail)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selected) { detail in
            TrophyRuleSheet(detail: detail)
        }
    }

    private func cell(badge: Badge, detail: TrophyDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(detail.title)
                .font(Theme.sans(15, weight: .bold))
                .foregroundStyle(detail.isEarned ? Theme.charcoal : Theme.warmGrey)
            if detail.isEarned {
                Text(levelLine(badge: badge, detail: detail))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.warmGrey)
            } else {
                Text(badge.hint)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.warmGrey)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func levelLine(badge: Badge, detail: TrophyDetail) -> String {
        let number = detail.level.flatMap { badge.tiers.firstIndex(of: $0) }.map { $0 + 1 } ?? 1
        let progress = detail.next?.currentLabel ?? detail.subtitle
        return "Level \(number) · \(progress)"
    }
}

private struct TrophyRuleSheet: View {
    let detail: TrophyDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(detail.isEarned ? "Earned" : "Not yet")
            Text(detail.title)
                .font(Theme.display(28))
                .foregroundStyle(Theme.charcoal)
            Text(detail.subtitle)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.warmGrey)
            Text(detail.rule)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
            if let earnedAt = detail.earnedAt {
                Text("First on \(FrayedFormat.dayStamp(earnedAt))")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.warmGrey)
            }
            if let next = detail.next {
                Text("Next: \(next.targetLabel)")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.warmGrey)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.frayedPrimary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
