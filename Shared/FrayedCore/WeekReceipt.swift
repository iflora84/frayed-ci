import Foundation

/// The weekly recap share card in numbers: seven lines and the totals the
/// thermal-paper receipt prints. Pure: built from cached DayRecaps and the
/// calendar, never from the clock unless `now` is left to default.
struct WeekReceipt: Hashable {
    struct Line: Hashable, Identifiable {
        let day: Date
        /// "Mon"
        let weekday: String
        let dayType: DayType?
        /// "Just a Monday", "Watch off", "Not yet"
        let typeLabel: String
        let stillSpikes: Int
        /// The day's median recovery in minutes; nil when none was seen settling.
        let recoveryMinutes: Int?
        let worn: Bool

        var id: Date {
            return day
        }
    }

    struct Calmest: Hashable {
        let line: Line
        let at: Date
        let bpm: Int
    }

    static let cameDownLimitMinutes = 60
    static let notYetLabel = "Not yet"
    static let watchOffLabel = "Watch off"

    let week: DateInterval
    /// calendar weekOfYear
    let weekNumber: Int
    /// "Sep 21 – 27"
    let rangeLabel: String
    /// Always 7, the calendar's first weekday first.
    let lines: [Line]
    let stillSpikes: Int
    /// Every still spike had a known recovery of an hour or less.
    let everyOneCameDown: Bool
    let cameDownAverageMinutes: Int?
    let fastest: Line?
    let asleepAverageMinutes: Int?
    let calmest: Calmest?
    let wornDays: Int
    /// "2026 W39 0006": year, week, count of receipts so far.
    let receiptNumber: String
    /// 7 entries, 2...9, from each day's still spikes.
    let barcodeWidths: [Double]

    static func build(week: DateInterval, recaps: [DayRecap], receiptCount: Int = 0,
                      calendar: Calendar, now: Date = Date()) -> WeekReceipt {
        let byKey = Dictionary(recaps.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })

        var lines: [Line] = []
        var day = calendar.startOfDay(for: week.start)
        for _ in 0..<7 {
            let recap = byKey[dayKey(day, calendar: calendar)]
            lines.append(line(day: day, recap: recap, calendar: calendar, now: now))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        }

        let recapsInWeek = lines.compactMap { byKey[dayKey($0.day, calendar: calendar)] }
            .filter { !$0.isNotWorn }
        let stills = recapsInWeek.flatMap { $0.stillSpikes }
        let stillCount = stills.count
        let recovered = stills.compactMap { $0.recoveryMinutes }
        let everyOneCameDown = stillCount > 0 && recovered.count == stillCount
            && recovered.allSatisfy { $0 <= cameDownLimitMinutes }

        let dailyMedians = lines.compactMap { $0.recoveryMinutes }
        let cameDownAverage = mean(dailyMedians)
        let fastest = lines.filter { $0.recoveryMinutes != nil }
            .min { ($0.recoveryMinutes ?? 0) < ($1.recoveryMinutes ?? 0) }

        let asleep = recapsInWeek.compactMap { $0.lastNight?.asleepMinutes }
        let calmest = calmestOfWeek(lines: lines, byKey: byKey, calendar: calendar)

        let weekNumber = calendar.component(.weekOfYear, from: week.start)
        let year = calendar.component(.yearForWeekOfYear, from: week.start)

        return WeekReceipt(
            week: week,
            weekNumber: weekNumber,
            rangeLabel: rangeLabel(week: week, calendar: calendar),
            lines: lines,
            stillSpikes: stillCount,
            everyOneCameDown: everyOneCameDown,
            cameDownAverageMinutes: cameDownAverage,
            fastest: fastest,
            asleepAverageMinutes: mean(asleep),
            calmest: calmest,
            wornDays: lines.filter { $0.worn }.count,
            receiptNumber: String(format: "%d W%02d %04d", year, weekNumber, receiptCount),
            barcodeWidths: lines.map { Double(2 + min($0.stillSpikes, 7)) }
        )
    }

    // MARK: Lines

    static func line(day: Date, recap: DayRecap?, calendar: Calendar, now: Date) -> Line {
        let weekday = String(RecapCopy.weekday(of: day, calendar: calendar).prefix(3))
        let worn = recap.map { !$0.isNotWorn } ?? false
        return Line(
            day: day,
            weekday: weekday,
            dayType: recap?.type,
            typeLabel: typeLabel(day: day, recap: recap, calendar: calendar, now: now),
            stillSpikes: worn ? (recap?.counts.still ?? 0) : 0,
            recoveryMinutes: worn ? recap?.recovery?.median.map { Int($0.rounded()) } : nil,
            worn: worn
        )
    }

    /// The recap's own label when it has one, else the type's name, else
    /// "Watch off" for an unworn or missing past day and "Not yet" for a day
    /// that has not started.
    static func typeLabel(day: Date, recap: DayRecap?, calendar: Calendar, now: Date) -> String {
        if day > now {
            return notYetLabel
        }
        guard let recap = recap, !recap.isNotWorn else {
            return watchOffLabel
        }
        if let label = recap.text.typeLabel, !label.isEmpty {
            return label
        }
        if let type = recap.type {
            let values = ["weekday": RecapCopy.weekday(of: day, calendar: calendar), "n": "\(recap.counts.daytime)"]
            return RecapCopy.typeName(type, values: values)
        }
        return notYetLabel
    }

    // MARK: Totals

    private static func calmestOfWeek(lines: [Line], byKey: [String: DayRecap], calendar: Calendar) -> Calmest? {
        var best: Calmest? = nil
        for line in lines where line.worn {
            guard let recap = byKey[dayKey(line.day, calendar: calendar)], let c = recap.calmest else {
                continue
            }
            if let current = best, current.bpm <= c.bpm {
                continue
            }
            best = Calmest(line: line, at: c.at, bpm: c.bpm)
        }
        return best
    }

    /// "Sep 21 – 27", or "Sep 28 – Oct 4" across a month edge.
    static func rangeLabel(week: DateInterval, calendar: Calendar) -> String {
        let last = week.end.addingTimeInterval(-1)
        let startParts = calendar.dateComponents([.month, .day], from: week.start)
        let endParts = calendar.dateComponents([.month, .day], from: last)
        let startMonth = monthName(startParts.month ?? 1)
        let endMonth = monthName(endParts.month ?? 1)
        if startMonth == endMonth {
            return "\(startMonth) \(startParts.day ?? 0) – \(endParts.day ?? 0)"
        }
        return "\(startMonth) \(startParts.day ?? 0) – \(endMonth) \(endParts.day ?? 0)"
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func monthName(_ month: Int) -> String {
        return months[(month - 1 + 12) % 12]
    }

    /// "2026-09-22": the key RecapInput carries, the local calendar day.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func mean(_ values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
