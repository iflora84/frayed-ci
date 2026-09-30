import SwiftUI

/// The You tab: how fast the week came down, the grid, the trophies, the
/// receipt, and the way to Settings. Full = canvas R-You, Quiet = Q-You.
struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.uiMode) private var mode

    @State private var showingGrid = false
    @State private var showingTrophies = false

    var body: some View {
        NavigationStack {
            Group {
                if mode == .quiet {
                    quiet
                } else {
                    full
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.charcoal)
    }

    // MARK: Full

    private var full: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ScreenHeader(stamp: "You") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Theme.charcoal)
                            .padding(.leading, 10)
                    }
                    .accessibilityLabel("Settings")
                }

                bounceBackCard
                    .frayedCard()

                WeekHeatmapView(ledgers: model.ledgers, calendar: model.calendar)
                    .frayedCard(padding: 16)

                TrophiesSection(ledgers: model.ledgers, engine: model.trophies)
                    .frayedCard(padding: 16)

                ReceiptEntry()

                CrisisLine()
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var bounceBackCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow("Bounced back · avg")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(thisWeekMinutes.map { "\($0) min" } ?? "–")
                    .font(Theme.mono(28, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
                Text("this week")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.warmGrey)
            }
            Text(comparisonLine)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.warmGrey)
        }
    }

    // MARK: Quiet

    private var quiet: some View {
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

            VStack(alignment: .leading, spacing: 6) {
                Text(thisWeekMinutes.map { "\($0) min" } ?? "–")
                    .font(Theme.mono(44, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
                Text(quietSentence)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.warmGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 28)

            VStack(spacing: 0) {
                quietRow("This week") { showingGrid = true }
                quietRow("Trophies") { showingTrophies = true }
                ReceiptEntry()
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                NavigationLink {
                    SettingsView()
                } label: {
                    HStack {
                        Text("Settings")
                            .font(Theme.sans(16))
                            .foregroundStyle(Theme.charcoal)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.warmGrey)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
            .padding(.top, 28)

            Spacer()

            CrisisLine(text: "Need to talk? 988")
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .sheet(isPresented: $showingGrid) {
            quietSheet {
                WeekHeatmapView(ledgers: model.ledgers, calendar: model.calendar)
            }
        }
        .sheet(isPresented: $showingTrophies) {
            quietSheet {
                TrophiesSection(ledgers: model.ledgers, engine: model.trophies)
            }
        }
    }

    private func quietRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.charcoal)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.warmGrey)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private func quietSheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(24)
        }
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: Numbers

    private var thisWeekMinutes: Int? {
        return minutes(model.trophies.averageBounceBack(model.ledgers))
    }

    /// The same average for the week before this one.
    private var lastWeekMinutes: Int? {
        let engine = model.trophies
        let previous = engine.previousWeek(before: engine.week(containing: engine.now))
        let earlier = TrophyEngine(calendar: model.calendar, now: previous.end.addingTimeInterval(-1))
        return minutes(earlier.averageBounceBack(model.ledgers))
    }

    private func minutes(_ seconds: TimeInterval?) -> Int? {
        guard let seconds else {
            return nil
        }
        return Int((seconds / 60).rounded())
    }

    private var comparisonLine: String {
        guard thisWeekMinutes != nil else {
            return "Nothing has settled yet this week."
        }
        if let last = lastWeekMinutes {
            return "Last week was \(last)."
        }
        return "First week."
    }

    private var quietSentence: String {
        guard let now = thisWeekMinutes else {
            return "No spike has settled yet this week."
        }
        if let last = lastWeekMinutes {
            return "How long a spike took to come down this week, on average. Last week it was \(last)."
        }
        return "How long a spike took to come down this week, on average. First week: \(now) is the number to beat."
    }
}
