import SwiftUI

/// One line of "Today, in order": last night, every spike, and the calmest
/// stretch, sorted by when they happened.
struct StoryRow: Identifiable {
    enum Kind {
        case asleep(DayRecap.LastNight)
        case spike(DayRecap.Spike)
        case calmest(DayRecap.Calmest)
    }

    let id: String
    let time: Date
    let kind: Kind

    static func rows(for recap: DayRecap) -> [StoryRow] {
        var rows: [StoryRow] = []
        if let night = recap.lastNight {
            rows.append(StoryRow(id: "asleep", time: night.start, kind: .asleep(night)))
        }
        for spike in recap.spikes {
            rows.append(StoryRow(id: spike.id, time: spike.start, kind: .spike(spike)))
        }
        if let calmest = recap.calmest {
            rows.append(StoryRow(id: "calmest", time: calmest.at, kind: .calmest(calmest)))
        }
        return rows.sorted { $0.time < $1.time }
    }

    var spike: DayRecap.Spike? {
        if case .spike(let s) = kind {
            return s
        }
        return nil
    }
}

/// The words for a spike row, shared by the recap screens and the share card.
enum StoryWords {
    static func title(_ spike: DayRecap.Spike) -> String {
        switch spike.bucket {
        case .workout:
            return "Workout"
        case .moving:
            return "Moving"
        case .inBed:
            return spike.inBedKind == .awake ? "In bed, awake" : "In bed, asleep"
        case .still:
            if let label = spike.label {
                if let name = label.title {
                    return "\u{201C}\(name)\u{201D}"
                }
                return "In a meeting"
            }
            return "Sitting still"
        }
    }

    /// The Quiet row's title: the user's own word or the event name, plain.
    static func quietTitle(_ spike: DayRecap.Spike) -> String {
        if spike.bucket == .still, let tag = spike.tag {
            return tag.label
        }
        if spike.bucket == .still, let name = spike.label?.title {
            return name
        }
        return title(spike)
    }

    /// "Peak 98 · nothing scheduled"; the tag comes back separately so the
    /// row can colour it.
    static func subline(_ spike: DayRecap.Spike) -> (text: String, tag: String?) {
        switch spike.bucket {
        case .workout, .moving:
            return ("Peak \(spike.peak) · on purpose", nil)
        case .inBed:
            return ("Peak \(spike.peak) · " + (spike.inBedKind == .awake ? "back to sleep" : "while asleep"), nil)
        case .still:
            if let label = spike.label {
                let who: String
                switch label.people {
                case 0: who = "Solo block"
                case 1: who = "One-to-one"
                default: who = "\(label.people) people"
                }
                return ("\(who) · peak \(spike.peak)", spike.tag?.label)
            }
            if let tag = spike.tag {
                return ("Peak \(spike.peak) · ", tag.label)
            }
            return ("Peak \(spike.peak) · nothing scheduled", nil)
        }
    }

    static func mark(_ spike: DayRecap.Spike) -> SettleMark {
        let kind: SettleMark.Kind
        switch spike.bucket {
        case .still: kind = .still
        case .workout, .moving: kind = .workout
        case .inBed: kind = .inBed
        }
        let height = min(max(Double(spike.magnitude) / 60, 0), 1)
        var settledAt: Double? = nil
        if spike.recoveredAt != nil {
            let minutes = Double(spike.recoveryMinutes ?? 0)
            settledAt = min(max(minutes / 60, 0.3), 0.9)
        }
        return SettleMark(kind: kind, height: height, settledAt: settledAt)
    }

    /// Right column: ("8 min", "settled"), ("—", "not yet"), ("40 min", "moving").
    static func result(_ spike: DayRecap.Spike, slowest: Bool) -> (value: String, note: String) {
        switch spike.bucket {
        case .workout, .moving:
            return (FrayedFormat.minutes(max(spike.elevatedMinutes, 1)), "moving")
        case .inBed, .still:
            if let minutes = spike.recoveryMinutes {
                return (FrayedFormat.minutes(minutes), slowest ? "slowest" : "settled")
            }
            return ("\u{2014}", "not yet")
        }
    }

    static func wakeUps(_ night: DayRecap.LastNight) -> String {
        return night.awakenings == 1 ? "1 wake-up" : "\(night.awakenings) wake-ups"
    }

    /// The slowest known come-down among the still spikes, when there is a
    /// second one to compare it with.
    static func slowestStillId(_ recap: DayRecap) -> String? {
        let known = recap.stillSpikes.filter { $0.recoveryMinutes != nil }
        guard known.count >= 2 else {
            return nil
        }
        return known.max { ($0.recoveryMinutes ?? 0) < ($1.recoveryMinutes ?? 0) }?.id
    }

    /// "Late", "Morning", "Midday", "Afternoon", "Evening" for the share card.
    static func partOfDay(_ date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 0..<5, 22...23: return "Late"
        case 5..<12: return "Morning"
        case 12..<14: return "Midday"
        case 14..<18: return "Afternoon"
        default: return "Evening"
        }
    }
}

/// "Today, in order". Full mode draws the card with the settle marks;
/// `compact` is the Quiet list: time, a title and one phrase, nothing else.
/// Pass `onTag` to make every spike open its detail (still ones take a
/// word there); leave it nil on a share card. `showsChart` puts the day's
/// heart-rate curve at the top of the card.
struct StoryListView: View {
    let recap: DayRecap
    var compact = false
    var showsChart = false
    var onTag: ((SpikeTag?, String) -> Void)? = nil

    @State private var opened: OpenedSpike? = nil

    private var rows: [StoryRow] {
        return StoryRow.rows(for: recap)
    }

    var body: some View {
        let rows = self.rows
        let slowest = StoryWords.slowestStillId(recap)
        VStack(spacing: 0) {
            if showsChart {
                chart
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, slowest: slowest)
                if index < rows.count - 1 && !isCalmest(row) && !isCalmest(rows[index + 1]) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
        }
        .modifier(ListChrome(compact: compact))
        .sheet(item: $opened) { item in
            SpikeDetailView(spike: item.spike, beats: recap.beats ?? [],
                            onTag: onTag.map { tagSpike -> (SpikeTag?) -> Void in { tag in tagSpike(tag, item.spike.id) } })
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let beats = recap.beats, let first = beats.first, let last = beats.last, first.at < last.at {
            let span = first.at...last.at
            let select: ((DayRecap.Spike) -> Void)? = onTag == nil ? nil : { opened = OpenedSpike(spike: $0) }
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Heart rate · tap a dot")
                HeartCurve(beats: beats, span: span, resting: recap.restingHR,
                           spikes: recap.spikes.filter { span.contains($0.peakAt) },
                           onSelect: select)
                    .frame(height: 120)
            }
            .padding(.vertical, 10)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private func isCalmest(_ row: StoryRow) -> Bool {
        if case .calmest = row.kind {
            return !compact
        }
        return false
    }

    @ViewBuilder
    private func rowView(_ row: StoryRow, slowest: String?) -> some View {
        if onTag != nil, let spike = row.spike {
            let wantsWord = spike.bucket == .still && spike.tag == nil
            Button {
                opened = OpenedSpike(spike: spike)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    rowContent(row, slowest: slowest)
                    if wantsWord {
                        addWord
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(wantsWord ? "Opens the curve and the words to pick from" : "Opens the curve")
        } else {
            rowContent(row, slowest: slowest)
        }
    }

    /// The visible way in for a new user: an untagged still spike asks.
    private var addWord: some View {
        Label("Add a word", systemImage: "plus")
            .font(Theme.sans(12, weight: .semibold))
            .foregroundStyle(Theme.apricotInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.apricotWash.opacity(0.35), in: Capsule())
            .padding(.leading, compact ? 60 : 62)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func rowContent(_ row: StoryRow, slowest: String?) -> some View {
        if compact {
            QuietRow(row: row)
        } else {
            FullRow(row: row, slowest: slowest)
        }
    }
}

private struct OpenedSpike: Identifiable {
    let spike: DayRecap.Spike

    var id: String {
        return spike.id
    }
}

private struct ListChrome: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content
        } else {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}

// MARK: Full row

private struct FullRow: View {
    let row: StoryRow
    let slowest: String?

    var body: some View {
        switch row.kind {
        case .asleep(let night):
            line(time: night.start, timeColor: Theme.charcoal,
                 title: "Asleep", titleColor: Theme.charcoal,
                 subline: "Up at \(FrayedFormat.clock(night.end).time) · \(StoryWords.wakeUps(night))", tag: nil,
                 mark: SettleMark(kind: .inBed, height: 0.2, settledAt: nil),
                 value: FrayedFormat.minutes(night.asleepMinutes), valueColor: Theme.skyInk, note: "in bed")
        case .spike(let spike):
            let sub = StoryWords.subline(spike)
            let result = StoryWords.result(spike, slowest: spike.id == slowest)
            let dim = spike.bucket == .workout || spike.bucket == .moving
            line(time: spike.start, timeColor: dim ? Theme.warmGrey : Theme.charcoal,
                 title: StoryWords.title(spike), titleColor: dim ? Theme.warmGrey : Theme.charcoal,
                 subline: sub.text, tag: sub.tag,
                 mark: StoryWords.mark(spike),
                 value: result.value, valueColor: dim ? Theme.warmGrey : Theme.charcoal, note: result.note)
        case .calmest(let calmest):
            line(time: calmest.at, timeColor: Theme.skyInk,
                 title: "Calmest", titleColor: Theme.charcoal,
                 subline: "Steadiest stretch today", tag: nil,
                 mark: SettleMark(kind: .flat, height: 0, settledAt: nil),
                 value: "\(calmest.bpm)", valueColor: Theme.skyInk, note: "bpm")
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.skyWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, -8)
        }
    }

    private func line(time: Date, timeColor: Color, title: String, titleColor: Color,
                      subline: String, tag: String?, mark: SettleMark,
                      value: String, valueColor: Color, note: String) -> some View {
        let clock = FrayedFormat.clock(time)
        return HStack(alignment: .center, spacing: 8) {
            Text("\(Text(clock.time).font(Theme.mono(12, weight: .bold)).foregroundStyle(timeColor)) \(Text(clock.meridiem).font(Theme.mono(9)).foregroundStyle(Theme.warmGrey))")
                .lineLimit(1)
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.sans(14, weight: .bold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                sublineText(subline, tag: tag)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            mark
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(Theme.mono(12.5, weight: .bold))
                    .foregroundStyle(valueColor)
                Text(note)
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.warmGrey)
            }
            .lineLimit(1)
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func sublineText(_ text: String, tag: String?) -> Text {
        let base = Text(text).font(Theme.sans(11.5)).foregroundStyle(Theme.warmGrey)
        guard let tag else {
            return base
        }
        let joiner = text.hasSuffix(" ") ? "" : " · "
        let word = Text(tag).font(Theme.sans(11.5, weight: .bold)).foregroundStyle(Theme.apricotInk)
        return Text("\(base)\(Text(joiner).font(Theme.sans(11.5)).foregroundStyle(Theme.warmGrey))\(word)")
    }
}

// MARK: Quiet row

private struct QuietRow: View {
    let row: StoryRow

    var body: some View {
        HStack(spacing: 10) {
            Text(Theme.stamp(row.time, "HH:mm"))
                .font(Theme.mono(16))
                .foregroundStyle(Theme.warmGrey)
                .frame(width: 50, alignment: .leading)
            Text(title)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.charcoal)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(trailing)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.warmGrey)
                .lineLimit(1)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var title: String {
        switch row.kind {
        case .asleep: return "Asleep"
        case .spike(let spike): return StoryWords.quietTitle(spike)
        case .calmest: return "Calmest"
        }
    }

    private var trailing: String {
        switch row.kind {
        case .asleep(let night):
            return "\(FrayedFormat.minutes(night.asleepMinutes)), \(StoryWords.wakeUps(night))"
        case .spike(let spike):
            switch spike.bucket {
            case .workout, .moving:
                return "on purpose"
            case .inBed, .still:
                if let minutes = spike.recoveryMinutes {
                    return "came down in \(FrayedFormat.minutes(minutes))"
                }
                return "not down yet"
            }
        case .calmest(let calmest):
            return "\(calmest.bpm) bpm"
        }
    }
}
