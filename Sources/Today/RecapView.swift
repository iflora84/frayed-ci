import SwiftUI
import UIKit

/// The Recap tab: today's recap in the mode the user picked, with the
/// Health states in front of it (no access, no recap yet, Watch not worn).
struct RecapView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.uiMode) private var mode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: mode == .quiet ? 24 : 10) {
                    header
                    content
                }
                .padding(.horizontal, mode == .quiet ? 24 : 20)
                .padding(.top, mode == .quiet ? 24 : 10)
                .padding(.bottom, 24)
            }
            .background(Theme.paper.ignoresSafeArea())
            .refreshable {
                await model.refreshRecap()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            model.markRecapOpened()
        }
    }

    private var day: Date {
        return model.today?.displayDay ?? Date()
    }

    @ViewBuilder
    private var header: some View {
        if mode == .quiet {
            HStack(alignment: .lastTextBaseline) {
                Wordmark()
                Spacer()
                Text(FrayedFormat.longDay(day))
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.warmGrey)
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
        } else {
            ScreenHeader(stamp: "Recap · \(FrayedFormat.dayStamp(day)) · No. \(max(model.recapNumber, 1))")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.healthStatus {
        case .denied, .unavailable:
            RecapNotice(
                title: model.healthStatus == .unavailable ? "No Apple Health on this device." : "Frayed can't read Apple Health.",
                body: model.healthStatus == .unavailable
                    ? "The recap reads heart rate, sleep and workouts from Apple Health, which this device doesn't have."
                    : "The recap reads heart rate, sleep and workouts from Apple Health. Turn on Heart Rate, Sleep and Workouts for Frayed in Settings.",
                compact: mode == .quiet
            ) {
                if model.healthStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .buttonStyle(.frayedPrimary)
                }
            }
        case .unknown:
            RecapNotice(
                title: "Your recap starts with Apple Health.",
                body: "Heart rate, sleep and workouts, read on this iPhone. Nothing leaves it.",
                compact: mode == .quiet
            ) {
                Button("Allow Apple Health") {
                    Task { await model.requestHealthAccess() }
                }
                .buttonStyle(.frayedPrimary)
            }
        case .authorized:
            if let today = model.today {
                if today.isNotWorn {
                    RecapNotice(
                        title: "Not much Watch time today.",
                        body: today.text.headline,
                        compact: mode == .quiet
                    ) {
                        EmptyView()
                    }
                } else if mode == .quiet {
                    RecapQuietView(recap: today)
                } else {
                    RecapFullView(recap: today, number: model.recapNumber)
                }
            } else {
                RecapNotice(
                    title: "Your first recap is on its way at \(RecapPresentation.clock(model.recapSchedule)).",
                    body: "Wear the Watch, go about the day. The recap writes itself.",
                    compact: mode == .quiet
                ) {
                    Button {
                        Task { await model.refreshRecap() }
                    } label: {
                        HStack(spacing: 6) {
                            if model.isRefreshing {
                                ProgressView().tint(Theme.warmGrey)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Check now")
                        }
                    }
                    .buttonStyle(.frayedOutline)
                    .disabled(model.isRefreshing)
                }
            }
        }
        if model.healthStatus != .authorized || model.today == nil || model.today?.isNotWorn == true {
            CrisisLine()
                .padding(.top, 8)
        }
    }
}

/// One explanatory block: a card in Full, plain text with air in Quiet.
private struct RecapNotice<Action: View>: View {
    let title: String
    let message: String
    let compact: Bool
    let action: Action

    init(title: String, body: String, compact: Bool, @ViewBuilder action: () -> Action) {
        self.title = title
        self.message = body
        self.compact = compact
        self.action = action()
    }

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.display(compact ? 28 : 22, relativeTo: .title))
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(Theme.sans(compact ? 16 : 14))
                .foregroundStyle(compact ? Theme.charcoal : Theme.warmGrey)
                .fixedSize(horizontal: false, vertical: true)
            action
                .padding(.top, 4)
        }
        if compact {
            stack
        } else {
            stack.frayedCard()
        }
    }
}

/// Bits both modes and both share cards read from a recap.
enum RecapPresentation {
    /// The recap's day, from the engine's dayKey ("2026-09-24" or "20260924"),
    /// falling back to the generation time.
    static func day(of recap: DayRecap) -> Date {
        for format in ["yyyy-MM-dd", "yyyyMMdd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: recap.dayKey) {
                return date
            }
        }
        return recap.generatedAt
    }

    /// The headline with "came down" on the butter highlighter when the
    /// sentence has it, so it still wraps like one paragraph.
    static func headline(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: "came down") {
            attributed[range].backgroundColor = Theme.butter
        }
        return attributed
    }

    /// "8 pm", "8:30 pm".
    static func clock(_ schedule: RecapNotification.Schedule) -> String {
        let hour12 = schedule.hour % 12 == 0 ? 12 : schedule.hour % 12
        let suffix = schedule.hour < 12 ? "am" : "pm"
        if schedule.minute == 0 {
            return "\(hour12) \(suffix)"
        }
        return String(format: "%d:%02d %@", hour12, schedule.minute, suffix)
    }

    /// "7 spikes · every one came down · avg 9 min", each part only when true.
    static func oneLine(_ recap: DayRecap) -> String {
        let n = recap.counts.daytime
        var parts = [n == 1 ? "1 spike" : "\(n) spikes"]
        let still = recap.stillSpikes
        if !still.isEmpty && still.allSatisfy({ $0.recoveredAt != nil }) {
            parts.append(still.count == 1 ? "it came down" : "every one came down")
        }
        if let median = recap.recovery?.median {
            parts.append("avg \(Int(median.rounded())) min")
        }
        return parts.joined(separator: " · ")
    }
}

extension DayRecap {
    var displayDay: Date {
        return RecapPresentation.day(of: self)
    }
}
