import SwiftUI

/// First run, after the age gate and the lock: welcome, the mode picker,
/// Apple Health, the recap time, done. Shown once. Quiet-style air: one
/// thing per screen, 24 pt gutters, no decoration.
struct OnboardingView: View {
    static let doneKey = "onboarding.done"

    private enum Step {
        case welcome, mode, health, time, done
    }

    let onDone: () -> Void

    @EnvironmentObject private var model: AppModel
    @State private var step: Step = .welcome
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isCentered {
                Wordmark(size: 20)
                    .padding(.top, 12)
                Spacer(minLength: 24)
            }
            switch step {
            case .welcome:
                welcome
            case .mode:
                ModePickerView { step = model.healthStatus == .unavailable ? .time : .health }
            case .health:
                health
            case .time:
                time
            case .done:
                done
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    /// Welcome and done sit in the middle of the screen, button pinned below.
    private var isCentered: Bool {
        return step == .welcome || step == .done
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Wordmark(size: 44)
            Text("The opposite of a highlight reel: a place where you don't have to be fine.")
                .font(Theme.title)
                .foregroundStyle(Theme.charcoal)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            Button("Continue") {
                step = .mode
            }
            .buttonStyle(.frayedPrimary)
        }
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your Watch already keeps notes.")
                .font(Theme.title)
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
            Text("Frayed reads heart rate, sleep, steps, workouts and any caffeine you log from Apple Health to write your evening recap. It stays on this iPhone unless you post a recap, and then only the few numbers on the card leave.")
                .font(Theme.body)
                .foregroundStyle(Theme.warmGrey)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 16)
            if isWorking {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                Button("Allow Apple Health") {
                    Task { await allowHealth() }
                }
                .buttonStyle(.frayedPrimary)
                Button("Not now") {
                    step = .time
                }
                .buttonStyle(.frayedOutline)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var time: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your recap arrives once a day. Pick when.")
                .font(Theme.title)
                .foregroundStyle(Theme.charcoal)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Recap time", selection: scheduleBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 16)
            Button("Continue") {
                Task { await allowNotifications() }
            }
            .buttonStyle(.frayedPrimary)
            .disabled(isWorking)
        }
    }

    private var done: some View {
        Text("That's it. Your first recap is on its way at \(scheduleLabel).")
            .font(Theme.title)
            .foregroundStyle(Theme.charcoal)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Button("Open Frayed", action: onDone)
                    .buttonStyle(.frayedPrimary)
            }
    }

    /// The wheel edits a Date; only its hour and minute reach the schedule.
    private var scheduleBinding: Binding<Date> {
        return Binding(
            get: {
                let s = model.recapSchedule
                return model.calendar.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = model.calendar.dateComponents([.hour, .minute], from: date)
                model.recapSchedule = RecapNotification.Schedule(hour: parts.hour ?? RecapNotification.defaultHour,
                                                                 minute: parts.minute ?? RecapNotification.defaultMinute)
            }
        )
    }

    /// "8:00 pm".
    private var scheduleLabel: String {
        let clock = FrayedFormat.clock(scheduleBinding.wrappedValue, calendar: model.calendar)
        return "\(clock.time) \(clock.meridiem)"
    }

    private func allowHealth() async {
        isWorking = true
        await model.requestHealthAccess()
        isWorking = false
        step = .time
    }

    private func allowNotifications() async {
        isWorking = true
        await model.requestNotificationPermission()
        isWorking = false
        step = .done
    }
}
