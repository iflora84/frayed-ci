import Foundation

/// The 16+ rule behind the age gate (SPEC 1.6): anonymous posting and
/// stress content. A wrong answer here blocks someone for good, so it
/// compares calendar days only: the time of day a date picker happens to
/// carry never matters. Someone born on Feb 29 comes of age on Mar 1 in a
/// non-leap year.
enum AgePolicy {
    static let minimumAge = 16

    /// `minimumAge` or older on the calendar day of `now`.
    static func isAdult(birthDate: Date, now: Date, calendar: Calendar) -> Bool {
        let birth = calendar.dateComponents([.year, .month, .day], from: birthDate)
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let birthYear = birth.year, let birthMonth = birth.month, let birthDay = birth.day,
              let year = today.year, let month = today.month, let day = today.day else {
            return false
        }
        let age = year - birthYear
        if age != minimumAge {
            return age > minimumAge
        }
        return (month, day) >= (birthMonth, birthDay)
    }
}
