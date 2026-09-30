import SwiftUI

/// The one Full-mode post card (canvas R-Feed): avatar, name, meta, day-type
/// pill, more menu; the body by kind; reactions under a hairline.
struct PostCard: View {
    let post: FeedPost

    @EnvironmentObject private var model: AppModel
    @State private var notice: FeedNotice?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch post {
            case .own(let moment):
                RecapTitle(moment: moment)
                if let summary = moment.recap {
                    CountsRow(summary: summary)
                }
            case .sample(let sample):
                if !sample.headline.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.headline)
                            .font(Theme.sans(17, weight: .bold))
                            .foregroundStyle(Theme.charcoal)
                        if !sample.subline.isEmpty {
                            Text(sample.subline)
                                .font(Theme.sans(12.5))
                                .foregroundStyle(sublineColor(sample.body))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                sampleBody(sample)
            }
            footer
            if post.isAnonymous {
                Text("Anonymous posts take preset reactions only.")
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.warmGrey)
                    .padding(.top, -3)
            }
        }
        .frayedCard(padding: 12)
        .feedNotice($notice)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            AuthorLink(post: post) {
                HStack(spacing: 10) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.author)
                            .font(Theme.sans(14, weight: .bold))
                            .foregroundStyle(Theme.charcoal)
                            .lineLimit(1)
                        Text(post.meta)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.warmGrey)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            if let label = post.dayTypeLabel {
                DayTypePill(text: label)
            }
            PostMenu(isOwn: post.isOwn, notice: $notice)
        }
    }

    @ViewBuilder private var avatar: some View {
        switch post {
        case .own:
            ZStack {
                Circle().fill(Theme.charcoal)
                Text("YOU")
                    .font(Theme.sans(10, weight: .bold))
                    .foregroundStyle(Theme.paper)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
        case .sample(let sample):
            Avatar(initials: sample.initials, anonymous: sample.anonymous)
        }
    }

    // MARK: Bodies

    private func sublineColor(_ body: FeedSampleBody) -> Color {
        if case .payStub = body {
            return Theme.skyInk
        }
        return Theme.warmGrey
    }

    @ViewBuilder private func sampleBody(_ sample: FeedSample) -> some View {
        switch sample.body {
        case .payStub(let lines):
            PayStub(lines: lines)
        case .permissionSlip(let text, let signed):
            PermissionSlip(text: text, signed: signed, author: sample.author)
        case .recap(let summary):
            CountsRow(summary: summary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 6) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(visibleKinds) { kind in
                            ReactionChip(kind: kind, count: count(for: kind), selected: isSelected(kind)) {
                                model.toggle(kind, on: post.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                Spacer(minLength: 0)
                trailingAction
            }
        }
    }

    @ViewBuilder private var trailingAction: some View {
        switch post {
        case .own(let moment):
            ShareLink(item: shareText(moment)) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Share")
                }
                .font(Theme.sans(12, weight: .bold))
                .foregroundStyle(Theme.charcoal)
            }
        case .sample(let sample):
            if !sample.anonymous {
                Button {
                    notice = FeedNotice(title: "Comments arrive with friends",
                                        message: "This is a sample post. Comments open once your first friend joins.")
                } label: {
                    Text("Comment")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.warmGrey)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var visibleKinds: [ReactionKind] {
        switch post {
        case .own:
            return [.hug, .same]
        case .sample(let sample):
            let picked = model.reactions[post.id] ?? []
            return ReactionKind.allCases.filter { (sample.reactionCounts[$0] ?? 0) > 0 || picked.contains($0) }
        }
    }

    private func isSelected(_ kind: ReactionKind) -> Bool {
        return model.reactions[post.id]?.contains(kind) ?? false
    }

    private func count(for kind: ReactionKind) -> Int {
        var base = 0
        if case .sample(let sample) = post {
            base = sample.reactionCounts[kind] ?? 0
        }
        return base + (isSelected(kind) ? 1 : 0)
    }

    private func shareText(_ moment: Moment) -> String {
        let n = moment.recap?.spikeCount ?? 0
        var line = n == 1 ? "1 spike." : "\(n) spikes."
        if n > 0, moment.recap?.recoverySeconds != nil {
            line += n == 1 ? " It came down." : " Every one came down."
        }
        if let label = post.dayTypeLabel {
            line += " \(label)."
        }
        return line + " · Frayed"
    }
}

// MARK: Recap title

/// "7 spikes. Every one came down." with the come-down highlighted only when
/// the recap knows a recovery, and the "About 9 min · slept 6 h 12" subline.
struct RecapTitle: View {
    let moment: Moment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            headline
                .font(Theme.sans(17, weight: .bold))
                .foregroundStyle(Theme.charcoal)
            if let subline {
                subline
                    .font(Theme.sans(12.5))
                    .foregroundStyle(Theme.warmGrey)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var headline: some View {
        let n = moment.recap?.spikeCount ?? 0
        if n == 0 {
            Text("Nothing to report. Your heart kept to itself.")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                let count = Text("\(n)").font(Theme.mono(17, weight: .bold))
                Text("\(count)\(n == 1 ? " spike. " : " spikes. ")")
                if moment.recap?.recoverySeconds != nil {
                    Text(n == 1 ? "It " : "Every one ")
                    Highlight(text: "came down")
                    Text(".")
                } else {
                    Text("Came down: couldn't tell.")
                }
            }
        }
    }

    private var subline: Text? {
        var parts: [Text] = []
        if let seconds = moment.recap?.recoverySeconds {
            let minutes = Double(seconds) / 60
            if minutes >= 60 {
                parts.append(Text("Over an hour to come down, avg"))
            } else {
                let rounded = max(1, Int(minutes.rounded()))
                let value = Text("\(rounded) min").font(Theme.mono(12.5, weight: .bold))
                parts.append(Text("About \(value) to come down, avg"))
            }
        }
        if let asleep = moment.night?.asleepMinutes, asleep > 0 {
            let slept = Text(FrayedFormat.minutes(asleep)).font(Theme.mono(12.5, weight: .bold))
            parts.append(Text("slept \(slept)"))
        }
        guard var out = parts.first else {
            return nil
        }
        for part in parts.dropFirst() {
            out = Text("\(out) · \(part)")
        }
        return out
    }
}

// MARK: Counts row

/// The three daytime counts of a recap, since a post carries the summary only.
struct CountsRow: View {
    let summary: Moment.RecapSummary

    var body: some View {
        HStack(spacing: 0) {
            column("Sitting still", summary.stillCount)
            column("Moving", summary.movingCount)
            column("Workouts", summary.workoutCount)
        }
        .frayedInset(padding: 8)
    }

    private func column(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Eyebrow(label)
            Text("\(count)")
                .font(Theme.mono(15, weight: .bold))
                .foregroundStyle(Theme.charcoal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Pay stub

struct PayStub: View {
    let lines: [FeedSampleLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("Pay stub · night shift".uppercased())
                    .font(Theme.mono(11, weight: .bold))
                    .kerning(0.9)
                    .foregroundStyle(Theme.charcoal)
                Spacer()
                Text("No. 0119")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.warmGrey)
            }
            .padding(.bottom, 2)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.label)
                        .font(Theme.mono(11))
                    Spacer()
                    Text(line.value)
                        .font(Theme.mono(11, weight: .bold))
                }
                .foregroundStyle(Theme.charcoal)
            }
        }
        .frayedInset(padding: 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Permission slip

struct PermissionSlip: View {
    let text: String
    let signed: String
    var author: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Permission slip")
                Spacer()
                Text(signed)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.warmGrey)
                    .lineLimit(1)
            }
            emphasised
                .font(Theme.sans(13.5))
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frayedInset(padding: 9)
    }

    /// The author's name bold inside the sentence, as on the canvas.
    private var emphasised: Text {
        guard !author.isEmpty, let range = text.range(of: author) else {
            return Text(text)
        }
        let name = Text(author).font(Theme.sans(13.5, weight: .bold))
        return Text("\(String(text[..<range.lowerBound]))\(name)\(String(text[range.upperBound...]))")
    }
}

// MARK: More menu and notices

struct FeedNotice: Identifiable {
    let title: String
    let message: String

    var id: String { title }
}

struct PostMenu: View {
    let isOwn: Bool
    @Binding var notice: FeedNotice?

    var body: some View {
        Menu {
            if !isOwn {
                Button("Report") {
                    notice = FeedNotice(title: "Reported", message: "Nothing changes on a sample post. Reports reach a person once friends arrive.")
                }
                Button("Block") {
                    notice = FeedNotice(title: "Blocked", message: "Nothing changes on a sample post. Blocking works once friends arrive.")
                }
            }
            Button("Hide") {
                notice = FeedNotice(title: "Hidden", message: "Hiding arrives with the next update. The post stays for now.")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.warmGrey)
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel(isOwn ? "More: hide" : "More: report or block")
    }
}

extension View {
    /// One alert for the feed's placeholder actions.
    func feedNotice(_ notice: Binding<FeedNotice?>) -> some View {
        return alert(
            notice.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { notice.wrappedValue != nil },
                set: { shown in
                    if !shown {
                        notice.wrappedValue = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(notice.wrappedValue?.message ?? "")
        }
    }
}
