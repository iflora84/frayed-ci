import SwiftUI

/// One spike opened from Recap: its curve, the numbers, and for a still
/// spike the words to pick from. Picking keeps the sheet open so the user
/// sees the choice land.
struct SpikeDetailView: View {
    let spike: DayRecap.Spike
    let beats: [DayRecap.Beat]
    /// nil where tagging is not offered (a past day, a share card).
    let onTag: ((SpikeTag?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var tag: SpikeTag?

    /// Minutes of context either side of the spike.
    private static let margin: TimeInterval = 15 * 60

    init(spike: DayRecap.Spike, beats: [DayRecap.Beat], onTag: ((SpikeTag?) -> Void)?) {
        self.spike = spike
        self.beats = beats
        self.onTag = onTag
        _tag = State(initialValue: spike.tag)
    }

    private var span: ClosedRange<Date> {
        let end = max(spike.recoveredAt ?? spike.end, spike.end)
        return spike.start.addingTimeInterval(-SpikeDetailView.margin)...end.addingTimeInterval(SpikeDetailView.margin)
    }

    private var windowBeats: [DayRecap.Beat] {
        return beats.filter { span.contains($0.at) }
    }

    private var canTag: Bool {
        return onTag != nil && spike.bucket == .still
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    curve
                    numbers
                    if canTag {
                        words
                    }
                }
                .padding(24)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        let clock = FrayedFormat.clock(spike.start)
        return VStack(alignment: .leading, spacing: 4) {
            Eyebrow("\(clock.time) \(clock.meridiem)")
            Text(StoryWords.title(spike))
                .font(Theme.display(28, relativeTo: .title))
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var curve: some View {
        let points = windowBeats
        VStack(alignment: .leading, spacing: 6) {
            if points.count >= 2 {
                HeartCurve(beats: points, span: span, resting: spike.resting, spikes: [spike],
                           shaded: spike.start...max(spike.recoveredAt ?? spike.end, spike.end),
                           tickFormat: "h:mm")
                    .frame(height: 170)
                    .accessibilityLabel("Heart rate rose from resting \(spike.resting) to \(spike.peak)")
            } else {
                StoryWords.mark(spike)
                    .frame(height: 60)
                Text("No minute-by-minute curve saved for this one.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.warmGrey)
            }
            Text("Dashed line: your resting \(spike.resting) bpm.")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.warmGrey)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var numbers: some View {
        HStack(spacing: 0) {
            stat("\(spike.peak)", "peak bpm")
            stat("+\(spike.magnitude)", "over resting")
            stat(spike.recoveryMinutes.map { FrayedFormat.minutes($0) } ?? "\u{2014}",
                 spike.recoveryMinutes == nil ? "not down yet" : "to come down")
            stat(FrayedFormat.minutes(max(spike.elevatedMinutes, 1)), "elevated")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.mono(17, weight: .bold))
                .foregroundStyle(Theme.charcoal)
            Text(label)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.warmGrey)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What was it?")
                .font(Theme.sans(17, weight: .bold))
                .foregroundStyle(Theme.charcoal)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(SpikeTag.allCases, id: \.rawValue) { option in
                    wordButton(option)
                }
            }
            if tag != nil {
                Button("Clear the word") {
                    pick(nil)
                }
                .font(Theme.sans(14))
                .foregroundStyle(Theme.warmGrey)
                .padding(.top, 2)
            }
        }
    }

    private func wordButton(_ option: SpikeTag) -> some View {
        let selected = tag == option
        return Button {
            pick(option)
        } label: {
            Text(option.label)
                .font(Theme.sans(14, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Theme.card : Theme.charcoal)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? Theme.apricotInk : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.apricotInk : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pick(_ option: SpikeTag?) {
        tag = option
        onTag?(option)
    }
}
