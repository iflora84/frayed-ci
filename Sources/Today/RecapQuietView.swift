import SwiftUI

/// Canvas Q-Recap: the day in a sentence, the rest behind one tap.
struct RecapQuietView: View {
    @EnvironmentObject private var model: AppModel

    let recap: DayRecap

    @State private var showOrder = false
    @State private var shareItem: ShareItem? = nil

    /// Still spikes with no word yet, so the collapsed list still asks.
    private var untagged: Int {
        return recap.stillSpikes.filter { $0.tag == nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(RecapPresentation.headline(recap.text.headline))
                    .font(Theme.display(28, relativeTo: .title))
                    .foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                if let type = recap.text.typeLabel {
                    Text(type + ".")
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.charcoal)
                }
                if let note = recap.text.addOns.first ?? recap.text.typeOneLiner {
                    Text(note)
                        .font(Theme.sans(13))
                        .italic()
                        .foregroundStyle(Theme.warmGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(RecapPresentation.oneLine(recap))
                .font(Theme.sans(16))
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showOrder.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Text("Today, in order")
                            .font(Theme.sans(16))
                            .foregroundStyle(Theme.charcoal)
                        Spacer()
                        if !showOrder && untagged > 0 {
                            Text(untagged == 1 ? "1 without a word" : "\(untagged) without a word")
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.apricotInk)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.warmGrey)
                            .rotationEffect(.degrees(showOrder ? 90 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                if showOrder {
                    StoryListView(recap: recap, compact: true) { tag, spikeId in
                        model.setTag(tag, spikeId: spikeId)
                    }
                    .padding(.top, 4)
                }
            }

            if let suggestion = recap.text.suggestion ?? recap.suggestion?.text, !suggestion.isEmpty {
                Text(suggestion)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                PostDayControl(recap: recap)
                    .padding(.bottom, 8)
                Button {
                    shareItem = CardRenderer.image(DayShareCardView(recap: recap, mode: .quiet), width: 390, height: 693).map { ShareItem(image: $0) }
                } label: {
                    Text("Share today")
                        .font(Theme.sans(16))
                        .underline()
                        .foregroundStyle(Theme.charcoal)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                Link(destination: URL(string: "tel:988")!) {
                    HStack(spacing: 0) {
                        Text("Need to talk? ")
                        Text("988").underline()
                    }
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.charcoal)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Call or text 988, the Suicide and Crisis Lifeline")
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
    }
}
