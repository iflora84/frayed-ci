import SwiftUI

/// One post opened from the feed. Your own shows the whole day behind it and
/// who can see it; a friend's shows only what they posted, numbers and
/// words, never a heart-rate curve (SPEC 1.6).
struct PostDetailView: View {
    let post: FeedPost

    @EnvironmentObject private var model: AppModel
    @Environment(\.uiMode) private var mode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .quiet {
                        QuietPost(post: post)
                    } else {
                        PostCard(post: post)
                    }
                    switch post {
                    case .own(let moment):
                        own(moment)
                    case .sample:
                        Text("Friends share the numbers on the card. Their heart-rate curve stays on their iPhone.")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.warmGrey)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
    }

    @ViewBuilder
    private func own(_ moment: Moment) -> some View {
        let dayKey = AppModel.dayKey(for: moment.start, calendar: model.calendar)
        if let recap = model.recaps.first(where: { $0.dayKey == dayKey }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("The day behind it")
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
                Text("Only you see this part.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.warmGrey)
                StoryListView(recap: recap, compact: mode == .quiet, showsChart: mode != .quiet)
            }
        }
        if moment.visibility != .private {
            HStack {
                Text(moment.visibility == .anonymous ? "Posted anonymously" : "Posted to friends")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.warmGrey)
                Spacer()
                Button("Take it down") {
                    model.setVisibility(.private, momentId: moment.id)
                    dismiss()
                }
                .buttonStyle(.frayedOutline)
            }
        }
    }
}

/// Recap's way into the feed. Nothing posts on its own: the recap stays
/// private until the user picks who sees it, and can be taken down again.
struct PostDayControl: View {
    let recap: DayRecap

    @EnvironmentObject private var model: AppModel
    @State private var asking = false

    var body: some View {
        if let moment = model.recapMoment(for: recap) {
            if moment.visibility == .private {
                Button {
                    asking = true
                } label: {
                    Label("Post today to the feed", systemImage: "paperplane")
                }
                .buttonStyle(.frayedOutline)
                .confirmationDialog("Who sees today?", isPresented: $asking, titleVisibility: .visible) {
                    Button("Friends") {
                        model.setVisibility(.friends, momentId: moment.id)
                    }
                    Button("Anonymous") {
                        model.setVisibility(.anonymous, momentId: moment.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("They see the day type and the counts. Your minute-by-minute heart rate stays on this iPhone.")
                }
            } else {
                HStack {
                    Label(moment.visibility == .anonymous ? "Posted anonymously" : "Posted to friends",
                          systemImage: "checkmark")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.warmGrey)
                    Spacer()
                    Button("Take it down") {
                        model.setVisibility(.private, momentId: moment.id)
                    }
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.charcoal)
                }
                .frame(minHeight: 44)
            }
        }
    }
}
