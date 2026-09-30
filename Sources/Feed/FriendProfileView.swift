import SwiftUI

/// A friend's history: the days they chose to post, newest first. Their
/// anonymous posts never show here, or the profile would unmask them, and
/// there is no heart-rate curve, only what each card already carried.
/// Until friends exist (Phase 5) it reads the sample posts.
struct FriendProfileView: View {
    let friend: FeedSample

    @Environment(\.uiMode) private var mode
    @Environment(\.dismiss) private var dismiss

    /// Free history is 7 days, for a friend's page as for your own.
    static let historyHours = 7 * 24

    static func posts(by friend: FeedSample) -> [FeedSample] {
        return (DemoData.friendPosts + DemoData.friendHistory)
            .filter { $0.author == friend.author && !$0.anonymous && $0.hoursAgo < historyHours }
            .sorted { $0.hoursAgo < $1.hoursAgo }
    }

    var body: some View {
        let posts = FriendProfileView.posts(by: friend)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Avatar(initials: friend.initials, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.author)
                                .font(Theme.display(26, relativeTo: .title))
                                .foregroundStyle(Theme.charcoal)
                            Text(posts.count == 1 ? "1 day posted this week" : "\(posts.count) days posted this week")
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.warmGrey)
                        }
                    }
                    .padding(.bottom, 4)
                    ForEach(posts) { sample in
                        if mode == .quiet {
                            QuietPost(post: .sample(sample))
                                .padding(.vertical, 8)
                        } else {
                            PostCard(post: .sample(sample))
                        }
                    }
                    Text("Only the days \(friend.author) chose to post. Anonymous posts never show here.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.warmGrey)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.opensFriendProfiles, false)
    }
}

/// A post's author line. For a named friend it opens their history; for
/// you, an anonymous post, or inside a profile it is plain.
struct AuthorLink<Label: View>: View {
    let post: FeedPost
    @ViewBuilder let label: () -> Label

    @Environment(\.opensFriendProfiles) private var enabled
    @State private var showing: FeedSample? = nil

    var body: some View {
        if enabled, let friend = post.friend {
            Button {
                showing = friend
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(friend.author)'s week")
            .sheet(item: $showing) { friend in
                FriendProfileView(friend: friend)
            }
        } else {
            label()
        }
    }
}

private struct OpensFriendProfilesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var opensFriendProfiles: Bool {
        get { self[OpensFriendProfilesKey.self] }
        set { self[OpensFriendProfilesKey.self] = newValue }
    }
}
