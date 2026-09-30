import SwiftUI

/// The Feed tab. Full (canvas R-Feed) stacks flat cards; Quiet (Q-Feed)
/// opens the newest post and lists the rest. Same posts in both.
struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.uiMode) private var mode
    @AppStorage("anon.mode") private var anonMode = false

    static let crisisURL = URL(string: "tel:988")!
    static let sampleNote = "Until your friends arrive · sample posts"
    static let emptyLine = "Nothing posted yet. Post a day from Recap when you want to."

    @State private var openPost: FeedPost?

    /// Only the recaps the user chose to post; the rest stay private.
    private var ownPosts: [FeedPost] {
        return model.moments.filter { $0.kind == .recap && $0.visibility != .private }.map { FeedPost.own($0) }
    }

    private var samplePosts: [FeedPost] {
        return DemoData.friendPosts.map { FeedPost.sample($0) }
    }

    /// Own recaps first, then samples while there are fewer than three posts.
    private var posts: [FeedPost] {
        let own = ownPosts
        if own.count < 3 {
            return own + samplePosts
        }
        return own
    }

    private var showsSamples: Bool {
        return ownPosts.count < 3
    }

    var body: some View {
        Group {
            if mode == .quiet {
                quiet
            } else {
                full
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(item: $openPost) { post in
            PostDetailView(post: post)
        }
    }

    // MARK: Full

    private var full: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScreenHeader {
                    HStack(spacing: 6) {
                        Link(destination: FeedView.crisisURL) {
                            HStack(spacing: 5) {
                                Image(systemName: "phone")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Need to talk? 988")
                                    .font(Theme.sans(12.5, weight: .bold))
                            }
                            .headerPill()
                        }
                        .accessibilityLabel("Call or text 988, the Suicide and Crisis Lifeline")
                        Button {
                            anonMode.toggle()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "theatermasks")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(anonMode ? "ANON ON" : "ANON OFF")
                                    .font(Theme.mono(11, weight: .bold))
                                    .kerning(0.6)
                            }
                            .headerPill()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(anonMode ? "Anonymous mode, on" : "Anonymous mode, off")
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text("\(posts.count) NEW").font(Theme.mono(11, weight: .bold)).foregroundStyle(Theme.charcoal)) · \(FrayedFormat.dayStamp(Date()).uppercased())")
                    Spacer()
                    Text("No likes here. Only support.".uppercased())
                }
                .font(Theme.mono(11))
                .kerning(0.7)
                .foregroundStyle(Theme.warmGrey)
                .padding(.top, -4)

                if ownPosts.isEmpty {
                    Text(FeedView.emptyLine)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.warmGrey)
                        .frayedCard()
                }
                ForEach(ownPosts) { post in
                    openable(PostCard(post: post), post)
                }
                if showsSamples {
                    Eyebrow(FeedView.sampleNote)
                        .padding(.top, 4)
                    ForEach(samplePosts) { post in
                        openable(PostCard(post: post), post)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    /// The whole card opens the post; its own buttons (reactions, menu)
    /// still win the tap.
    private func openable<Card: View>(_ card: Card, _ post: FeedPost) -> some View {
        return card
            .contentShape(Rectangle())
            .onTapGesture { openPost = post }
            .accessibilityAction(named: "Open") { openPost = post }
    }

    // MARK: Quiet

    private var quiet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    Wordmark()
                    Spacer()
                    Text(FrayedFormat.longDay(Date()))
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.warmGrey)
                }
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }

                Text("\(Text("\(posts.count)").font(Theme.mono(13))) new")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.warmGrey)
                    .padding(.top, 24)

                if ownPosts.isEmpty {
                    Text(FeedView.emptyLine)
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.charcoal)
                        .padding(.top, 24)
                }

                if let first = posts.first {
                    openable(QuietPost(post: first), first)
                        .padding(.top, 24)
                }

                let rest = Array(posts.dropFirst())
                if !rest.isEmpty {
                    Text("Earlier")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.warmGrey)
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                    VStack(spacing: 0) {
                        ForEach(rest) { post in
                            Button {
                                openPost = post
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(post.author) · \(post.meta)")
                                        .font(Theme.sans(13))
                                        .foregroundStyle(Theme.warmGrey)
                                    Text(post.listHeadline)
                                        .font(Theme.sans(16))
                                        .foregroundStyle(Theme.charcoal)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                                .overlay(alignment: .top) {
                                    Rectangle().fill(Theme.hairline).frame(height: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }

                if showsSamples {
                    Text(FeedView.sampleNote)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.warmGrey)
                        .padding(.top, 12)
                }

                HStack {
                    Link(destination: FeedView.crisisURL) {
                        Text("Need to talk? \(Text("988").underline())")
                            .font(Theme.sans(16))
                            .foregroundStyle(Theme.charcoal)
                    }
                    .accessibilityLabel("Call or text 988, the Suicide and Crisis Lifeline")
                    Spacer()
                    Button(anonMode ? "Anon on" : "Anon off") {
                        anonMode.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.warmGrey)
                    .accessibilityLabel(anonMode ? "Anonymous mode, on" : "Anonymous mode, off")
                }
                .frame(minHeight: 44)
                .padding(.top, 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: Quiet post

/// One post in Quiet mode: name and time, the body in a plain card, the
/// reactions as text with the chosen one highlighted.
struct QuietPost: View {
    let post: FeedPost

    @EnvironmentObject private var model: AppModel
    @State private var notice: FeedNotice?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author)
                        .font(Theme.sans(16, weight: .bold))
                        .foregroundStyle(Theme.charcoal)
                    Text(post.meta)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.warmGrey)
                }
                Spacer()
                PostMenu(isOwn: post.isOwn, notice: $notice)
                    .frame(width: 44, height: 44)
                    .padding(.top, -10)
                    .padding(.trailing, -12)
            }

            postBody
                .padding(.top, 16)

            HStack(spacing: 24) {
                ForEach(visibleKinds) { kind in
                    QuietReaction(kind: kind, count: count(for: kind), selected: isSelected(kind)) {
                        model.toggle(kind, on: post.id)
                    }
                }
            }
            .padding(.top, 8)

            if post.isAnonymous {
                Text("Anonymous posts take preset reactions only.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.warmGrey)
                    .padding(.top, 4)
            }
        }
        .feedNotice($notice)
    }

    @ViewBuilder private var postBody: some View {
        switch post {
        case .own(let moment):
            VStack(alignment: .leading, spacing: 8) {
                RecapTitle(moment: moment)
                if let summary = moment.recap {
                    countsLine(summary)
                }
            }
            .frayedCard(padding: 20)
        case .sample(let sample):
            switch sample.body {
            case .permissionSlip(let text, let signed):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permission slip")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.warmGrey)
                    Text(text)
                        .font(Theme.sans(16))
                        .lineSpacing(5)
                        .foregroundStyle(Theme.charcoal)
                    Text(signed)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.warmGrey)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                }
                .frayedCard(padding: 20)
            case .payStub(let lines):
                VStack(alignment: .leading, spacing: 8) {
                    if !sample.headline.isEmpty {
                        Text(sample.headline)
                            .font(Theme.sans(16, weight: .bold))
                            .foregroundStyle(Theme.charcoal)
                    }
                    if !sample.subline.isEmpty {
                        Text(sample.subline)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.skyInk)
                    }
                    Text("Pay stub · night shift")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.warmGrey)
                        .padding(.top, 8)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.label)
                                .font(Theme.sans(16))
                            Spacer()
                            Text(line.value)
                                .font(Theme.mono(16, weight: .bold))
                        }
                        .foregroundStyle(Theme.charcoal)
                    }
                }
                .frayedCard(padding: 20)
            case .recap(let summary):
                VStack(alignment: .leading, spacing: 8) {
                    if !sample.headline.isEmpty {
                        Text(sample.headline)
                            .font(Theme.sans(16, weight: .bold))
                            .foregroundStyle(Theme.charcoal)
                    }
                    if !sample.subline.isEmpty {
                        Text(sample.subline)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.warmGrey)
                    }
                    countsLine(summary)
                }
                .frayedCard(padding: 20)
            }
        }
    }

    private func countsLine(_ summary: Moment.RecapSummary) -> some View {
        let still = Text("\(summary.stillCount)").font(Theme.mono(13))
        let moving = Text("\(summary.movingCount)").font(Theme.mono(13))
        let workouts = Text("\(summary.workoutCount)").font(Theme.mono(13))
        return Text("Sitting still \(still) · Moving \(moving) · Workouts \(workouts)")
            .font(Theme.sans(13))
            .foregroundStyle(Theme.warmGrey)
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
}

/// Quiet mode's reaction: plain text, the chosen one on butter.
private struct QuietReaction: View {
    let kind: ReactionKind
    let count: Int
    let selected: Bool
    let action: () -> Void

    private var label: Text {
        guard count > 0 else {
            return Text(kind.title)
        }
        return Text("\(kind.title) \(Text("\(count)").font(Theme.mono(16, weight: .bold)))")
    }

    var body: some View {
        Button(action: action) {
            label
                .font(Theme.sans(16, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.charcoal : Theme.warmGrey)
                .padding(.horizontal, selected ? 6 : 0)
                .padding(.vertical, 1)
                .background(selected ? Theme.butter : Color.clear)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(kind.title), \(count)" : kind.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Header pills

private struct HeaderPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.charcoal)
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Theme.charcoal, lineWidth: 1))
            .lineLimit(1)
            .fixedSize()
    }
}

private extension View {
    func headerPill() -> some View {
        return modifier(HeaderPill())
    }
}
