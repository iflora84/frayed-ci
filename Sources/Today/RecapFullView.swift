import SwiftUI

/// Canvas R-Recap: the whole day in order, every card flat and uniform.
struct RecapFullView: View {
    @EnvironmentObject private var model: AppModel

    let recap: DayRecap
    var number: Int = 0

    @State private var shareItem: ShareItem? = nil
    @State private var breathing = false
    @State private var replaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headline
            sourceStrip
            story
            recovery
            if let suggestion = recap.text.suggestion ?? recap.suggestion?.text, !suggestion.isEmpty {
                suggestionCard(suggestion)
            }
            PostDayControl(recap: recap)
                .padding(.top, 2)
            Button {
                shareItem = CardRenderer.image(DayShareCardView(recap: recap, mode: .full, number: number), width: 390, height: 693).map { ShareItem(image: $0) }
            } label: {
                Label("Share today's card", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.frayedPrimary)
            .padding(.top, 2)
            CrisisLine()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
        .sheet(isPresented: $breathing) {
            BreathingSheet()
        }
    }

    // MARK: Headline

    private var headline: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(RecapPresentation.headline(recap.text.headline))
                    .font(Theme.display(28, relativeTo: .title))
                    .foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = recap.text.addOns.first ?? recap.text.typeOneLiner {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Eyebrow("Notes from the Wrist")
                        Text(note)
                            .font(Theme.sans(11.5))
                            .italic()
                            .foregroundStyle(Theme.warmGrey)
                            .lineLimit(2)
                    }
                }
                if recap.text.footerUnderHeadline {
                    Text(recap.text.footer)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.warmGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if recap.counts.still > 0 {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.top, 1)
                        Text(calledLine)
                            .font(Theme.sans(13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.charcoal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let type = recap.text.typeLabel {
                DayTypePill(text: type)
                    .padding(.top, 4)
            }
        }
    }

    private var calledLine: AttributedString {
        let noticed = recap.counts.noticed
        let still = recap.counts.still
        var line: AttributedString
        if noticed == 0 {
            line = AttributedString(still == 1 ? "One sitting still. " : "\(still) sitting still. ")
            var hint = AttributedString("Tap one to put a word on it.")
            hint.foregroundColor = Theme.warmGrey
            line.append(hint)
        } else {
            line = AttributedString("You called \(noticed) of \(still). ")
            let left = still - noticed
            if left > 0 {
                var rest = AttributedString(left == 1 ? "One still without a word." : "\(left) still without a word.")
                rest.foregroundColor = Theme.warmGrey
                line.append(rest)
            }
        }
        return line
    }

    // MARK: Where the spikes came from

    private var sourceStrip: some View {
        let inBed = recap.counts.inBedAwake + recap.counts.inBedAsleep
        return HStack(spacing: 0) {
            sourceCell(count: recap.counts.workout + recap.counts.moving, label: workoutLabel, strong: false)
                .padding(.trailing, 8)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            sourceCell(count: recap.counts.still, label: "sitting still", strong: true)
                .padding(.horizontal, 10)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            sourceCell(count: inBed, label: inBedLabel, strong: false)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var workoutLabel: String {
        if let first = recap.spikes.first(where: { $0.bucket == .workout }) {
            let clock = FrayedFormat.clock(first.start)
            return "your \(clock.time) \(clock.meridiem) workout"
        }
        if recap.counts.moving > 0 {
            return "on the move"
        }
        return "in workouts"
    }

    private var inBedLabel: String {
        if let first = recap.spikes.first(where: { $0.bucket == .inBed }) {
            let clock = FrayedFormat.clock(first.start)
            return "\(clock.time) \(clock.meridiem), in bed"
        }
        return "in bed"
    }

    private func sourceCell(count: Int, label: String, strong: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(Theme.mono(20, weight: .bold))
                .foregroundStyle(Theme.charcoal)
            Text(label)
                .font(Theme.sans(12, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? Theme.charcoal : Theme.warmGrey)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Today, in order

    private var story: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today, in order")
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
                Spacer()
                Eyebrow("Resting \(recap.restingHR) bpm")
            }
            StoryListView(recap: recap, compact: false, showsChart: true) { tag, spikeId in
                model.setTag(tag, spikeId: spikeId)
            }
            .opacity(replaying ? 0.55 : 1)
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(SettleMark(kind: .still, height: 0.8, settledAt: nil), "Sitting still")
            legendItem(SettleMark(kind: .workout, height: 0.7, settledAt: nil), "Workout")
            legendItem(SettleMark(kind: .inBed, height: 0.3, settledAt: nil), "In bed")
            HStack(spacing: 5) {
                Circle().fill(Theme.skyInk).frame(width: 8, height: 8)
                Text("SETTLED")
            }
        }
        .font(Theme.mono(10.5))
        .kerning(0.5)
        .foregroundStyle(Theme.warmGrey)
        .padding(.top, 1)
    }

    private func legendItem(_ mark: SettleMark, _ label: String) -> some View {
        HStack(spacing: 5) {
            mark
                .scaleEffect(0.5, anchor: .center)
                .frame(width: 20, height: 8)
            Text(label.uppercased())
        }
    }

    // MARK: Recovery

    private var recovery: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Bounced back · avg")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(recap.recovery?.median.map { "\(Int($0.rounded())) min" } ?? "\u{2014}")
                        .font(Theme.mono(20, weight: .bold))
                        .foregroundStyle(Theme.apricotInk)
                    if let line = recap.text.recovery {
                        Text(line)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.warmGrey)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.easeInOut(duration: 0.35)) { replaying = true }
                Task {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    withAnimation(.easeInOut(duration: 0.6)) { replaying = false }
                }
            } label: {
                Label("Play the come-down", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.frayedOutline)
            .disabled(recap.recovery?.median == nil)
        }
        .padding(.top, 6)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: One suggestion

    private func suggestionCard(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "circle.circle")
                .symbolRenderingMode(.palette)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.apricot, Theme.warmGrey)
            Text(text)
                .font(Theme.sans(12.5))
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Breathe") {
                breathing = true
            }
            .buttonStyle(.frayedOutline)
        }
        .frayedCard(padding: 10)
    }
}

/// Two minutes of long exhales: the circle grows for 4 s, shrinks for 6 s.
struct BreathingSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var inhaling = false
    @State private var scale: CGFloat = 0.55
    @State private var remaining = 120
    @State private var finished = false

    private let total = 120

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.charcoal)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.skyWash)
                    .frame(width: 240, height: 240)
                Circle()
                    .fill(Theme.sky)
                    .frame(width: 240, height: 240)
                    .scaleEffect(scale)
            }
            Text(finished ? "That's two minutes." : (inhaling ? "Breathe in" : "Breathe out, slowly"))
                .font(Theme.display(24, relativeTo: .title2))
                .foregroundStyle(Theme.charcoal)
            Text(finished ? "Close it whenever." : Theme.clock(TimeInterval(remaining)))
                .font(Theme.mono(16))
                .foregroundStyle(Theme.warmGrey)
            Spacer()
            Text("In through the nose for 4, out for 6. Nothing to get right.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.warmGrey)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .task {
            await run()
        }
    }

    private func run() async {
        var elapsed = 0
        while elapsed < total && !Task.isCancelled {
            inhaling = true
            withAnimation(.easeInOut(duration: 4)) { scale = 1 }
            if await tick(seconds: 4, elapsed: &elapsed) { return }
            inhaling = false
            withAnimation(.easeInOut(duration: 6)) { scale = 0.55 }
            if await tick(seconds: 6, elapsed: &elapsed) { return }
        }
        finished = true
    }

    /// Counts down one second at a time; true when the view went away.
    private func tick(seconds: Int, elapsed: inout Int) async -> Bool {
        for _ in 0..<seconds {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return true
            }
            elapsed += 1
            remaining = max(total - elapsed, 0)
        }
        return false
    }
}
