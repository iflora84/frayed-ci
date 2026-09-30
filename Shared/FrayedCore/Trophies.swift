import Foundation

// Romp's trophies were per session. Frayed's are per day, because the recap
// is the unit the app talks about. They are computed from DayLedger values
// the recap owner hands over, so this file depends on nothing but
// Foundation. Every string describes what the body did, never the person.

/// A still spike that overlapped a calendar event. `title` is the event name
/// when the user shows titles and nil otherwise; it never leaves the device.
struct LabelledSpike: Hashable, Sendable {
    let title: String?
    /// Minutes from the peak back to resting + 10 (RECAP 4.3); nil when the
    /// Watch never saw it settle.
    let recoveryMinutes: Int?

    init(title: String? = nil, recoveryMinutes: Int? = nil) {
        self.title = title
        self.recoveryMinutes = recoveryMinutes
    }
}

/// One local day as the trophy rules see it: the seam between the recap
/// engine and the trophies. The recap owner builds one per recap day from
/// its own output (RECAP 9), with `day` from `calendar.startOfDay(for:)`.
struct DayLedger: Hashable, Identifiable, Sendable {
    /// Local midnight of the recap day.
    let day: Date
    /// The Watch produced readings that day (coverage > 0). An unworn day
    /// pauses the steady streak instead of breaking it (RECAP 6.10).
    var worn: Bool
    /// Enough readings for a day type: coverage of 0.5 or more and 8 h of
    /// awake tracking (RECAP 5). Quiet and zen days need it.
    var tracked: Bool
    var stillSpikes: Int
    var movingSpikes: Int
    var workoutSpikes: Int
    /// Rises while awake in bed.
    var nightRises: Int
    /// Median of the known recoveries in minutes (RECAP 4.3); nil when none
    /// of the day's still spikes was seen settling.
    var recoveryMedianMinutes: Double?
    var load: Int?
    /// Last night's 0-100 sleep score; nil without a sleep session.
    var sleepScore: Int?
    var asleepMinutes: Int?
    /// When last night's sleep session started.
    var bedtime: Date?
    var labelledSpikes: [LabelledSpike]
    /// The user opened this day's recap.
    var recapOpened: Bool

    var id: Date {
        return day
    }

    init(
        day: Date,
        worn: Bool = true,
        tracked: Bool = true,
        stillSpikes: Int = 0,
        movingSpikes: Int = 0,
        workoutSpikes: Int = 0,
        nightRises: Int = 0,
        recoveryMedianMinutes: Double? = nil,
        load: Int? = nil,
        sleepScore: Int? = nil,
        asleepMinutes: Int? = nil,
        bedtime: Date? = nil,
        labelledSpikes: [LabelledSpike] = [],
        recapOpened: Bool = false
    ) {
        self.day = day
        self.worn = worn
        self.tracked = tracked
        self.stillSpikes = stillSpikes
        self.movingSpikes = movingSpikes
        self.workoutSpikes = workoutSpikes
        self.nightRises = nightRises
        self.recoveryMedianMinutes = recoveryMedianMinutes
        self.load = load
        self.sleepScore = sleepScore
        self.asleepMinutes = asleepMinutes
        self.bedtime = bedtime
        self.labelledSpikes = labelledSpikes
        self.recapOpened = recapOpened
    }
}

/// Every number a trophy rule uses.
enum TrophyRules {
    /// Bounced back: at least this many still spikes, settled in at most
    /// `bounceBackMinutes` on average.
    static let bounceBackSpikes = 3
    static let bounceBackMinutes: Double = 8
    /// A calendar spike counts as got through when it settled within this.
    static let settledMinutes = 10
    /// Slept it off: a score of `restedScore` the night after a `heavyLoad` day.
    static let heavyLoad = 60
    static let restedScore = 80
    /// Early night: a full night, started this much earlier than the median
    /// of the last `usualNights` bedtimes (at least `baselineNights` known).
    static let fullNightMinutes = 7 * 60
    static let earlyNightLeadMinutes = 45
    static let usualNights = 7
    static let baselineNights = 3
    static let steadyDays = 7
}

/// What one day earned, shown on its recap card and in the moment detail.
enum DayTrophy: Hashable, Sendable {
    case fastestRecovery
    case calmestDay
    case bestNight
    case bouncedBack
    case sleptItOff
    /// The event title when the user shows titles, nil otherwise. Only
    /// `title` reads it, for the in-app detail; every surface that leaves the
    /// phone uses `shareTitle`.
    case gotThrough(String?)
    case earlyNight
    case quietDay

    /// The three all-time records; the rest are earned on the day's own terms.
    var isRecord: Bool {
        switch self {
        case .fastestRecovery, .calmestDay, .bestNight: return true
        case .bouncedBack, .sleptItOff, .gotThrough, .earlyNight, .quietDay: return false
        }
    }

    var title: String {
        switch self {
        case .fastestRecovery: return "Fastest bounce-back"
        case .calmestDay: return "Calmest day"
        case .bestNight: return "Best night"
        case .bouncedBack: return "Bounced back"
        case .sleptItOff: return "Slept it off"
        case .gotThrough(let label):
            guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
                return "Got through it"
            }
            return "Got through '\(label)'"
        case .earlyNight: return "Early night"
        case .quietDay: return "Quiet day"
        }
    }

    /// The title for posts, share cards, notifications and widgets: the same
    /// as `title` except that a calendar label never travels (RECAP 0.8, 3.3).
    var shareTitle: String {
        if case .gotThrough = self {
            return "Got through it"
        }
        return title
    }

    var subtitle: String {
        switch self {
        case .fastestRecovery, .calmestDay, .bestNight: return "all time"
        case .bouncedBack: return "spiked, never stayed"
        case .sleptItOff: return "heavy day, good night"
        case .gotThrough: return "and came down"
        case .earlyNight: return "earlier than your usual"
        case .quietDay: return "one spike or none"
        }
    }

    /// What it takes, in a sentence, for the detail sheet.
    var rule: String {
        switch self {
        case .fastestRecovery: return "A lower average bounce-back than any day before it."
        case .calmestDay: return "A lower load than any day before it."
        case .bestNight: return "A higher sleep score than any night before it."
        case .bouncedBack:
            return "\(TrophyRules.bounceBackSpikes) spikes or more while sitting still, back near resting "
                + "in about \(Int(TrophyRules.bounceBackMinutes)) minutes or less on average."
        case .sleptItOff:
            return "A sleep score of \(TrophyRules.restedScore) or more the night after a day "
                + "with a load of \(TrophyRules.heavyLoad) or more."
        case .gotThrough:
            return "A spike during a calendar event that settled within \(TrophyRules.settledMinutes) minutes."
        case .earlyNight:
            return "Asleep \(TrophyRules.fullNightMinutes / 60) hours or more, in bed at least "
                + "\(TrophyRules.earlyNightLeadMinutes) minutes before your usual time."
        case .quietDay: return "A full day on the wrist with one spike or none while sitting still."
        }
    }

    /// Stable key for posts and share cards. The label never travels with it.
    var key: String {
        switch self {
        case .fastestRecovery: return "fastest_recovery"
        case .calmestDay: return "calmest_day"
        case .bestNight: return "best_night"
        case .bouncedBack: return "bounced_back"
        case .sleptItOff: return "slept_it_off"
        case .gotThrough: return "got_through"
        case .earlyNight: return "early_night"
        case .quietDay: return "quiet_day"
        }
    }

    init?(key: String) {
        switch key {
        case "fastest_recovery": self = .fastestRecovery
        case "calmest_day": self = .calmestDay
        case "best_night": self = .bestNight
        case "bounced_back": self = .bouncedBack
        case "slept_it_off": self = .sleptItOff
        case "got_through": self = .gotThrough(nil)
        case "early_night": self = .earlyNight
        case "quiet_day": self = .quietDay
        default: return nil
        }
    }
}

/// The trophy case on You. Earned once, kept for good.
enum Badge: String, CaseIterable, Sendable {
    case bouncedBack, zenDay, sleptItOff, steady, gotThrough

    var title: String {
        switch self {
        case .bouncedBack: return "Bounced back"
        case .zenDay: return "Zen day"
        case .sleptItOff: return "Slept it off"
        case .steady: return "Steady"
        case .gotThrough: return "Got through"
        }
    }

    /// How to earn it, for the locked state.
    var hint: String {
        switch self {
        case .bouncedBack:
            return "A day of \(TrophyRules.bounceBackSpikes) spikes or more, settled in about "
                + "\(Int(TrophyRules.bounceBackMinutes)) minutes on average"
        case .zenDay: return "A full day on the wrist with no spike while sitting still"
        case .sleptItOff:
            return "A sleep score of \(TrophyRules.restedScore) or more after a day with a load of \(TrophyRules.heavyLoad) or more"
        case .steady: return "Your recap opened \(TrophyRules.steadyDays) days in a row"
        case .gotThrough: return "A spike during a calendar event that settled within \(TrophyRules.settledMinutes) minutes"
        }
    }

    /// Levels in `unit`; the first one earns the badge.
    var tiers: [Int] {
        switch self {
        case .steady: return [TrophyRules.steadyDays, 14, 30, 90, 365]
        case .bouncedBack, .zenDay, .sleptItOff, .gotThrough: return [1, 5, 25]
        }
    }

    /// The top level `current` has reached, nil below the first.
    func level(for current: Int) -> Int? {
        return tiers.last { $0 <= current }
    }

    var unit: TierUnit {
        return .days
    }

    var rule: String {
        switch self {
        case .bouncedBack: return DayTrophy.bouncedBack.rule
        case .zenDay: return "A full day on the wrist with no spike while sitting still. Zero, checked twice."
        case .sleptItOff: return DayTrophy.sleptItOff.rule
        case .steady: return "Open your recap \(TrophyRules.steadyDays) days in a row. A day without the Watch pauses the run instead of ending it."
        case .gotThrough: return DayTrophy.gotThrough(nil).rule
        }
    }
}

enum TierUnit: String, Sendable {
    case days, minutes

    func format(_ value: Int) -> String {
        switch self {
        case .days: return value == 1 ? "1 day" : "\(value) days"
        case .minutes: return "\(value) min"
        }
    }
}

/// How far along the next level is: "8 days" of "14 days".
struct TierProgress: Equatable, Sendable {
    let current: Int
    let target: Int
    let unit: TierUnit
    /// A bounce-back to beat is faster, not bigger.
    var lowerIsBetter: Bool = false

    var fraction: Double {
        if lowerIsBetter {
            guard current > 0 else {
                return 1
            }
            return min(max(Double(target) / Double(current), 0), 1)
        }
        guard target > 0 else {
            return 1
        }
        return min(max(Double(current) / Double(target), 0), 1)
    }

    var remaining: Int {
        return lowerIsBetter ? max(current - target, 0) : max(target - current, 0)
    }

    var currentLabel: String {
        return unit.format(current)
    }

    var targetLabel: String {
        return unit.format(target)
    }
}

/// Everything the trophy and badge detail sheet and its share card show.
/// Locked badges have no earnedAt.
struct TrophyDetail: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    /// What it takes, in a sentence or two.
    let rule: String
    /// Local midnight of the day that earned it; the recap of that day is
    /// the moment to link to.
    let earnedAt: Date?
    /// The next level, or the day to beat; nil once the top one is reached.
    let next: TierProgress?
    /// The highest badge level reached, in the badge's unit; nil for locked
    /// badges and day trophies. The medal art shows it.
    var level: Int? = nil

    var isEarned: Bool {
        return earnedAt != nil
    }
}

/// Spikes by attribution bucket (RECAP 3.1) for a day or a week.
struct AttributionCounts: Equatable, Sendable {
    let still: Int
    let moving: Int
    let workout: Int
    /// Rises while awake in bed; not part of the headline count.
    let night: Int

    var awake: Int {
        return still + moving + workout
    }
}

extension AttributionCounts {
    init(days: [DayLedger]) {
        self.init(
            still: days.reduce(0) { $0 + $1.stillSpikes },
            moving: days.reduce(0) { $0 + $1.movingSpikes },
            workout: days.reduce(0) { $0 + $1.workoutSpikes },
            night: days.reduce(0) { $0 + $1.nightRises }
        )
    }
}

struct DayCount: Equatable, Sendable {
    let day: DateInterval
    let count: Int
}

struct WeekBars: Equatable, Sendable {
    let thisWeek: [DayCount]
    let lastWeek: [DayCount]

    var thisWeekTotal: Int {
        return thisWeek.reduce(0) { $0 + $1.count }
    }

    var lastWeekTotal: Int {
        return lastWeek.reduce(0) { $0 + $1.count }
    }
}

/// Days in a row with the recap opened. Only the steady badge reads it;
/// You shows the average bounce-back instead of a streak number.
struct RecapStreak: Equatable, Sendable {
    let current: Int
    let best: Int
}

/// Everything is computed from the injected calendar and `now`, never from
/// the system clock or zone, so results are deterministic. Ledgers for days
/// after `now` never count.
struct TrophyEngine {
    let calendar: Calendar
    let now: Date

    // Weeks come from dateInterval(of:for:) rather than adding 7 * 86400,
    // so a week that crosses a DST change is 167 or 169 hours long.
    func week(containing date: Date) -> DateInterval {
        return calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date, duration: 0)
    }

    func previousWeek(before week: DateInterval) -> DateInterval {
        return self.week(containing: week.start.addingTimeInterval(-1))
    }

    // MARK: Day trophies

    /// Records and the day's own trophies. Like Romp's records, each record
    /// needs something to beat: the first day with a value sets none, and a
    /// tie is not a record.
    func dayTrophies(for day: DayLedger, history: [DayLedger]) -> [DayTrophy] {
        let others = past(history, excluding: day)
        var result: [DayTrophy] = []
        if let median = day.recoveryMedianMinutes,
           let best = others.compactMap({ $0.recoveryMedianMinutes }).min(), median < best {
            result.append(.fastestRecovery)
        }
        if let load = day.load, let best = others.compactMap({ $0.load }).min(), load < best {
            result.append(.calmestDay)
        }
        if let score = day.sleepScore, let best = others.compactMap({ $0.sleepScore }).max(), score > best {
            result.append(.bestNight)
        }
        if TrophyEngine.bouncedBack(day) {
            result.append(.bouncedBack)
        }
        if sleptItOff(day, history: others) {
            result.append(.sleptItOff)
        }
        if let spike = TrophyEngine.settledCalendarSpike(day) {
            result.append(.gotThrough(spike.title))
        }
        if earlyNight(day, history: others) {
            result.append(.earlyNight)
        }
        if TrophyEngine.quietDay(day) {
            result.append(.quietDay)
        }
        return result
    }

    static func bouncedBack(_ day: DayLedger) -> Bool {
        guard let median = day.recoveryMedianMinutes else {
            return false
        }
        return day.stillSpikes >= TrophyRules.bounceBackSpikes && median <= TrophyRules.bounceBackMinutes
    }

    static func zenDay(_ day: DayLedger) -> Bool {
        return day.tracked && day.stillSpikes == 0
    }

    static func quietDay(_ day: DayLedger) -> Bool {
        return day.tracked && day.stillSpikes <= 1
    }

    /// The first calendar spike that settled within the limit.
    static func settledCalendarSpike(_ day: DayLedger) -> LabelledSpike? {
        return day.labelledSpikes.first { spike in
            guard let minutes = spike.recoveryMinutes else {
                return false
            }
            return minutes <= TrophyRules.settledMinutes
        }
    }

    /// Needs the previous day's ledger in `history`.
    func sleptItOff(_ day: DayLedger, history: [DayLedger]) -> Bool {
        guard let score = day.sleepScore, score >= TrophyRules.restedScore,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: day.day),
              let load = history.first(where: { calendar.isDate($0.day, inSameDayAs: yesterday) })?.load else {
            return false
        }
        return load >= TrophyRules.heavyLoad
    }

    /// Early is measured against the user's own recent bedtimes, never a
    /// clock time, so it works for a night shift too.
    func earlyNight(_ day: DayLedger, history: [DayLedger]) -> Bool {
        guard let asleep = day.asleepMinutes, asleep >= TrophyRules.fullNightMinutes,
              let tonight = bedtimeOffset(day) else {
            return false
        }
        let usual = history
            .filter { $0.day < day.day }
            .sorted { $0.day < $1.day }
            .compactMap { bedtimeOffset($0) }
            .suffix(TrophyRules.usualNights)
        guard usual.count >= TrophyRules.baselineNights, let median = TrophyEngine.median(Array(usual)) else {
            return false
        }
        return tonight <= median - Double(TrophyRules.earlyNightLeadMinutes)
    }

    /// Minutes between the day's midnight and when sleep started: -40 for
    /// 23:20 the evening before, 30 for half past midnight.
    private func bedtimeOffset(_ day: DayLedger) -> Double? {
        guard let bedtime = day.bedtime else {
            return nil
        }
        return bedtime.timeIntervalSince(day.day) / 60
    }

    // MARK: Badges

    func earnedBadges(_ days: [DayLedger]) -> Set<Badge> {
        return Set(Badge.allCases.filter { badgeDetail($0, days: days).isEarned })
    }

    func badgeDetails(_ days: [DayLedger]) -> [TrophyDetail] {
        return Badge.allCases.map { badgeDetail($0, days: days) }
    }

    /// earnedAt is the day it was first earned; the progress is towards the
    /// level above the best so far.
    func badgeDetail(_ badge: Badge, days: [DayLedger]) -> TrophyDetail {
        let past = self.past(days)
        let current: Int
        let earnedAt: Date?
        if badge == .steady {
            let runs = runLengths(past)
            current = runs.map { $0.run }.max() ?? 0
            earnedAt = runs.first { $0.run >= TrophyRules.steadyDays }?.day
        } else {
            let hits = past.filter { counts($0, toward: badge, history: past) }
            current = hits.count
            earnedAt = hits.first?.day
        }
        return TrophyDetail(
            id: "badge-\(badge.rawValue)",
            title: badge.title,
            subtitle: earnedAt == nil ? "Not earned yet" : TrophyEngine.bestSoFar(current, badge: badge),
            rule: badge.rule,
            earnedAt: earnedAt,
            next: badge.tiers.first { $0 > current }.map { TierProgress(current: current, target: $0, unit: badge.unit) },
            level: earnedAt == nil ? nil : (badge.level(for: current) ?? badge.tiers[0])
        )
    }

    /// Whether one day counts toward a badge.
    func counts(_ day: DayLedger, toward badge: Badge, history: [DayLedger]) -> Bool {
        switch badge {
        case .bouncedBack: return TrophyEngine.bouncedBack(day)
        case .zenDay: return TrophyEngine.zenDay(day)
        case .sleptItOff: return sleptItOff(day, history: history)
        case .gotThrough: return TrophyEngine.settledCalendarSpike(day) != nil
        case .steady: return day.recapOpened
        }
    }

    /// Records have no next level. A bounce-back's progress is the fastest
    /// day so far, when there is a faster one.
    func trophyDetail(_ trophy: DayTrophy, for day: DayLedger, history: [DayLedger]) -> TrophyDetail {
        var next: TierProgress?
        if case .bouncedBack = trophy, let median = day.recoveryMedianMinutes {
            let others = past(history, excluding: day)
            if let best = others.compactMap({ $0.recoveryMedianMinutes }).min(), best < median {
                next = TierProgress(current: Int(median.rounded()), target: Int(best.rounded()), unit: .minutes, lowerIsBetter: true)
            }
        }
        return TrophyDetail(
            id: "trophy-\(dayKey(day.day))-\(trophy.key)",
            title: trophy.title,
            subtitle: trophy.subtitle,
            rule: trophy.rule,
            earnedAt: day.day,
            next: next
        )
    }

    // MARK: Streak

    /// The current run ends today, or yesterday while today's recap is still
    /// open. An unworn day pauses a run; a worn day without an opened recap,
    /// or a day with no ledger at all, ends it.
    func recapStreak(_ days: [DayLedger]) -> RecapStreak {
        let ascending = past(days)
        let best = runLengths(ascending).map { $0.run }.max() ?? 0

        let byDay = Dictionary(ascending.map { (calendar.startOfDay(for: $0.day), $0) },
                               uniquingKeysWith: { first, _ in first })
        var cursor = calendar.startOfDay(for: now)
        let today = byDay[cursor]
        if today?.recapOpened != true && today?.worn != false {
            cursor = previousDay(cursor)
        }
        var current = 0
        while let ledger = byDay[cursor] {
            if ledger.recapOpened {
                current += 1
            } else if ledger.worn {
                break
            }
            cursor = previousDay(cursor)
        }
        return RecapStreak(current: current, best: best)
    }

    /// The run length at every opened day, oldest first. Expects one ledger
    /// per day, ascending.
    private func runLengths(_ ascending: [DayLedger]) -> [(day: Date, run: Int)] {
        var result: [(day: Date, run: Int)] = []
        var run = 0
        var chainEnd: Date?
        for ledger in ascending {
            let continues = chainEnd.map { calendar.isDate(nextDay($0), inSameDayAs: ledger.day) } ?? false
            if ledger.recapOpened {
                run = continues ? run + 1 : 1
                chainEnd = ledger.day
                result.append((day: ledger.day, run: run))
            } else if !ledger.worn && continues {
                chainEnd = ledger.day
            } else {
                run = 0
                chainEnd = nil
            }
        }
        return result
    }

    // MARK: Week figures

    func attributionCounts(_ days: [DayLedger], in week: DateInterval) -> AttributionCounts {
        return AttributionCounts(days: past(days).filter { week.contains($0.day) && $0.day < week.end })
    }

    /// Mean of the daily median recoveries in the week containing `now`, in
    /// seconds for Theme.clock; nil until a day this week has one.
    func averageBounceBack(_ days: [DayLedger]) -> TimeInterval? {
        let week = self.week(containing: now)
        let values = past(days)
            .filter { week.contains($0.day) && $0.day < week.end }
            .compactMap { $0.recoveryMedianMinutes }
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count) * 60
    }

    /// One bucket per calendar day of `week`, in order. Takes plain dates
    /// (spike starts) so any list can be bucketed the same way.
    func dailyCounts(_ dates: [Date], in week: DateInterval) -> [DayCount] {
        var result: [DayCount] = []
        var day = week.start
        while day < week.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else {
                break
            }
            let end = min(next, week.end)
            let count = dates.filter { $0 >= day && $0 < end && $0 <= now }.count
            result.append(DayCount(day: DateInterval(start: day, end: end), count: count))
            day = end
        }
        return result
    }

    func weekBars(_ dates: [Date]) -> WeekBars {
        let thisWeek = week(containing: now)
        let lastWeek = previousWeek(before: thisWeek)
        return WeekBars(thisWeek: dailyCounts(dates, in: thisWeek), lastWeek: dailyCounts(dates, in: lastWeek))
    }

    // MARK: Helpers

    /// One ledger per local day up to today, oldest first. When two share a
    /// day the first one given wins.
    private func past(_ days: [DayLedger], excluding excluded: DayLedger? = nil) -> [DayLedger] {
        var seen = Set<Date>()
        if let excluded = excluded {
            seen.insert(calendar.startOfDay(for: excluded.day))
        }
        var result: [DayLedger] = []
        for ledger in days where ledger.day <= now {
            if seen.insert(calendar.startOfDay(for: ledger.day)).inserted {
                result.append(ledger)
            }
        }
        return result.sorted { $0.day < $1.day }
    }

    private func nextDay(_ date: Date) -> Date {
        return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
    }

    private func previousDay(_ date: Date) -> Date {
        return calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86400)
    }

    /// "20260922": the same per-day key the recap moment id uses.
    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld%02ld%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func bestSoFar(_ value: Int, badge: Badge) -> String {
        switch badge {
        case .steady: return "Best run: \(badge.unit.format(value))"
        case .bouncedBack, .zenDay, .sleptItOff, .gotThrough: return "\(badge.unit.format(value)) so far"
        }
    }
}
