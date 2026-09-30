import SwiftUI

/// The daily 9:16 card (canvas R-Share and Q-Share), drawn at 390 x 693 pt
/// and rendered at 3x. Plain values only: ImageRenderer has no environment.
struct DayShareCardView: View {
    static let size = CGSize(width: 390, height: 693)

    let recap: DayRecap
    var mode: UIMode = .full
    var number: Int = 0

    var body: some View {
        Group {
            if mode == .quiet {
                quiet
            } else {
                full
            }
        }
        .frame(width: DayShareCardView.size.width, height: DayShareCardView.size.height)
        .background(Theme.paper)
        .environment(\.colorScheme, .light)
    }

    // MARK: Full (R-Share)

    private var full: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Wordmark()
                Spacer()
                Eyebrow(FrayedFormat.dayStamp(recap.displayDay) + (number > 0 ? " · No. \(number)" : ""))
            }

            Text(RecapPresentation.headline(recap.text.headline))
                .font(Theme.display(32, relativeTo: .largeTitle))
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 342, alignment: .leading)
                .padding(.top, 18)
            if let named = namedLine {
                Text(named)
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.warmGrey)
                    .padding(.top, 8)
            }

            storyCard
                .padding(.top, 18)

            numbers
                .padding(.top, 16)

            ZStack(alignment: .topTrailing) {
                Text(recap.text.shareLine1 ?? recap.text.typeOneLiner ?? recap.text.headline)
                    .font(Theme.display(24, relativeTo: .title))
                    .foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 250, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let type = recap.text.typeLabel {
                    DayTypePill(text: type)
                        .padding(.top, 8)
                }
            }
            .padding(.top, 16)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 7) {
                Text("You don't have to be fine here.")
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
                HStack {
                    if let night = recap.lastNight {
                        Eyebrow("Slept \(FrayedFormat.minutes(night.asleepMinutes)) · \(StoryWords.wakeUps(night))")
                    } else {
                        Eyebrow("Resting \(recap.restingHR) bpm")
                    }
                    Spacer()
                    Wordmark(size: 14)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(Theme.charcoal).frame(height: 1) }
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24))
    }

    private var namedLine: String? {
        let noticed = recap.counts.noticed
        if noticed > 0 {
            return noticed == 1 ? "I put a name on one of them." : "I put a name on \(noticed) of them."
        }
        return recap.text.attribution
    }

    private var storyCard: some View {
        let rows = Array(StoryRow.rows(for: recap).prefix(6))
        let slowest = StoryWords.slowestStillId(recap)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today, in order")
                    .font(Theme.sans(12.5, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Theme.skyInk).frame(width: 8, height: 8)
                    Eyebrow("settled · resting \(recap.restingHR)")
                }
            }
            .padding(.bottom, 3)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                cardRow(row, slowest: slowest)
                if index < rows.count - 1, !isCalmest(row) {
                    DashedRule(color: Theme.hairline)
                }
            }
        }
        .frayedCard(padding: 14)
    }

    private func isCalmest(_ row: StoryRow) -> Bool {
        if case .calmest = row.kind {
            return true
        }
        return false
    }

    @ViewBuilder
    private func cardRow(_ row: StoryRow, slowest: String?) -> some View {
        switch row.kind {
        case .asleep(let night):
            cardLine(part: "Late", partColor: Theme.warmGrey, title: Text("Asleep").font(Theme.sans(12, weight: .bold)).foregroundStyle(Theme.charcoal),
                     mark: SettleMark(kind: .inBed, height: 0.2, settledAt: nil),
                     value: FrayedFormat.minutes(night.asleepMinutes), valueColor: Theme.skyInk)
        case .spike(let spike):
            let dim = spike.bucket == .workout || spike.bucket == .moving
            let result = StoryWords.result(spike, slowest: spike.id == slowest)
            cardLine(part: StoryWords.partOfDay(row.time), partColor: Theme.warmGrey, title: cardTitle(spike),
                     mark: StoryWords.mark(spike),
                     value: result.value, valueColor: dim ? Theme.warmGrey : Theme.charcoal)
        case .calmest(let calmest):
            cardLine(part: "Midday", partColor: Theme.skyInk, title: Text("Calmest").font(Theme.sans(12, weight: .bold)).foregroundStyle(Theme.charcoal),
                     mark: SettleMark(kind: .flat, height: 0, settledAt: nil),
                     value: "\(calmest.bpm) bpm", valueColor: Theme.skyInk)
            .padding(.horizontal, 6)
            .background(Theme.skyWash, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(.horizontal, -6)
        }
    }

    @ViewBuilder
    private func cardTitle(_ spike: DayRecap.Spike) -> some View {
        if spike.bucket == .still, let tag = spike.tag {
            DayTypePill(text: tag.label)
        } else {
            let dim = spike.bucket == .workout || spike.bucket == .moving
            Text(dim ? StoryWords.title(spike) + ", on purpose" : StoryWords.title(spike))
                .font(Theme.sans(12, weight: .bold))
                .foregroundStyle(dim ? Theme.warmGrey : Theme.charcoal)
                .lineLimit(1)
        }
    }

    private func cardLine<Title: View>(part: String, partColor: Color, title: Title, mark: SettleMark,
                                       value: String, valueColor: Color) -> some View {
        HStack(spacing: 6) {
            Text(part.uppercased())
                .font(Theme.mono(11, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(partColor)
                .frame(width: 64, alignment: .leading)
            title
                .frame(maxWidth: .infinity, alignment: .leading)
            mark
            Text(value)
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private var numbers: some View {
        HStack(spacing: 0) {
            numberCell(Text("\(recap.counts.daytime)"), label: "spikes")
                .padding(.trailing, 6)
            DashedRule(color: Theme.hairline, vertical: true)
            numberCell(Text("\(recap.counts.still)"), label: "sitting still")
                .padding(.horizontal, 12)
            DashedRule(color: Theme.hairline, vertical: true)
            numberCell(bounceText, label: "to bounce back, avg")
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var bounceText: Text {
        guard let median = recap.recovery?.median else {
            return Text("\u{2014}")
        }
        var minutes = AttributedString("\(Int(median.rounded()))")
        minutes.backgroundColor = Theme.butter
        return Text("\(Text(minutes))\(Text(" min").font(Theme.mono(13, weight: .bold)).foregroundStyle(Theme.apricotInk))")
    }

    private func numberCell(_ number: Text, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            number
                .font(Theme.mono(26, weight: .bold))
                .foregroundStyle(Theme.charcoal)
            Text(label)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.warmGrey)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Quiet (Q-Share)

    private var quiet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Wordmark()
                Spacer()
                Text(FrayedFormat.longDay(recap.displayDay))
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.warmGrey)
            }
            Spacer(minLength: 0)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 18) {
                quietSentence
                    .font(Theme.display(36, relativeTo: .largeTitle))
                    .fixedSize(horizontal: false, vertical: true)
                Text(recap.text.shareLine2 ?? RecapPresentation.oneLine(recap))
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.warmGrey)
            }
            Spacer(minLength: 0)
                .frame(maxHeight: .infinity)
            Spacer(minLength: 0)
                .frame(maxHeight: 40)
            Text("You don't have to be fine here.")
                .font(Theme.sans(16, weight: .semibold))
                .foregroundStyle(Theme.charcoal)
        }
        .padding(32)
    }

    private var quietSentence: Text {
        if let type = recap.text.typeLabel, recap.typeStatus == .awarded, let line = recap.text.typeOneLiner {
            return Text("\(Text(type + ".").foregroundStyle(Theme.apricotInk))\n\(Text(line).foregroundStyle(Theme.charcoal))")
        }
        return Text(RecapPresentation.headline(recap.text.headline)).foregroundStyle(Theme.charcoal)
    }
}

/// A one-pixel dashed hairline, across or down.
struct DashedRule: View {
    var color: Color = Theme.hairline
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .overlay {
                DashedLine(vertical: vertical)
                    .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
    }

    private struct DashedLine: Shape {
        let vertical: Bool

        func path(in rect: CGRect) -> Path {
            var path = Path()
            if vertical {
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
            return path
        }
    }
}
