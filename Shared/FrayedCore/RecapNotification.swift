import Foundation

/// The daily recap notification (RECAP 8): one repeating calendar trigger
/// at the user's time, a discreet body with no numbers, and the rule that
/// stops it nagging when the Watch has not been worn. Pure: the app layer
/// turns a Schedule and a Decision into UNNotificationRequest calls.
enum RecapNotification {
    static let identifier = "recap-daily"
    static let threadIdentifier = "recap"
    static let title = "Frayed"
    static let relevanceScore = 0.6
    static let defaultHour = 20
    static let defaultMinute = 0

    /// Seeded by day (RECAP 6.1); none carries a number, a type or a duration.
    static let bodies = [
        "Your recap is in.",
        "Today, in a few lines. Whenever you're ready.",
        "The day's recap is ready. No rush.",
        "Recap's ready. Your heart kept notes.",
        "Ready when you are: today's recap."
    ]
    static let notWornBody = "Not much Watch time today. There's still a recap, a short one."
    static let sundayNudgeBody = "We've had nothing from the Watch this week. Tap if you want it back in the loop."

    /// Hour and minute of the repeating trigger, clamped like the profile does.
    struct Schedule: Hashable, Codable {
        let hour: Int
        let minute: Int

        init(hour: Int = RecapNotification.defaultHour, minute: Int = RecapNotification.defaultMinute) {
            self.hour = min(max(hour, 0), 23)
            self.minute = min(max(minute, 0), 59)
        }

        /// For UNCalendarNotificationTrigger(dateMatching:repeats: true).
        var dateComponents: DateComponents {
            return DateComponents(hour: hour, minute: minute)
        }

        /// The next fire date at or after `now` in the given calendar.
        func nextFireDate(after now: Date, calendar: Calendar) -> Date? {
            return calendar.nextDate(after: now, matching: dateComponents, matchingPolicy: .nextTime)
        }
    }

    enum Decision: Hashable {
        case send(body: String)
        case skip
        /// The once-a-week Sunday nudge after a silent week.
        case nudge(body: String)
    }

    static func body(picker: RecapCopy.Picker) -> String {
        return picker.pick(.notification, from: bodies) ?? bodies[0]
    }

    /// What to deliver at fire time. Two empty days in a row skip the
    /// notification; a silent week gets one Sunday nudge, never more.
    static func decision(coverageToday: Double, coverageYesterday: Double?, healthReadable: Bool = true,
                         date: Date, calendar: Calendar, nudgedThisWeek: Bool, picker: RecapCopy.Picker) -> Decision {
        let wornToday = healthReadable && coverageToday > 0
        if wornToday {
            return .send(body: body(picker: picker))
        }
        let wornYesterday = (coverageYesterday ?? 1) > 0
        if wornYesterday {
            return .send(body: notWornBody)
        }
        if calendar.component(.weekday, from: date) == 1 && !nudgedThisWeek {
            return .nudge(body: sundayNudgeBody)
        }
        return .skip
    }
}
