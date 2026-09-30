import XCTest
import Foundation

// The ten golden days from docs/RECAP.md section 7, with the variant picker
// forced to index 0 for every block, plus the banned-word sweep. Times are
// local wall-clock in America/Los_Angeles through an explicit calendar, as
// in FrayedCoreTests; this file never touches Fx so it stands on its own.
private enum RFx {
    static let zone = TimeZone(identifier: "America/Los_Angeles")!

    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 2
        return cal
    }()

    static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func date(_ s: String) -> Date {
        guard let d = parser.date(from: s) else {
            fatalError("bad test date: \(s)")
        }
        return d
    }
}

/// One fixture day. "HH:mm" resolves on the day key; a night start at or
/// after noon belongs to the evening before.
private struct Day {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    func at(_ hhmm: String, _ dayOffset: Int = 0) -> Date {
        let d = RFx.date("\(key) \(hhmm)")
        return RFx.calendar.date(byAdding: .day, value: dayOffset, to: d)!
    }

    func input(generatedAt: String = "20:00", resting: Int?, coverage: Double, awake: Double) -> RecapInput {
        return RecapInput(
            dayKey: key, dayStart: at("04:00"), now: at(generatedAt), recapTime: at("20:00"),
            userId: "fixture", restingHistory: resting.map { [$0] } ?? [],
            coverage: coverage, awakeTrackedHours: awake, crisisNumber: "988"
        )
    }

    func run(_ id: String, _ start: String, _ end: String, peakAt: String? = nil, peak: Int,
             stepsPad: Double? = nil, motion: RecapInput.Motion = .sedentary, recoveredAt: String? = nil,
             stage: RecapInput.SleepStage? = nil, tag: SpikeTag? = nil) -> RecapInput.Run {
        return RecapInput.Run(
            id: id, start: at(start), end: at(end), peakAt: at(peakAt ?? start), peak: peak,
            stepsPadded: stepsPad, motionActive: motion == .active,
            recoveredAt: recoveredAt.map { at($0) }, stage: stage, tag: tag
        )
    }

    func night(_ start: String, _ end: String, asleep: Int, awake: Int, awakenings: Int, lowHR: Int) -> RecapInput.Night {
        let startHour = Int(start.prefix(2)) ?? 0
        return RecapInput.Night(
            start: at(start, startHour >= 12 ? -1 : 0), end: at(end),
            asleepMinutes: asleep, awakeMinutes: awake, awakenings: awakenings, lowHR: lowHR
        )
    }

    /// One SDNN reading three hours into the night: the engine takes the median.
    func hrv(_ sdnn: Double, in night: RecapInput.Night) -> RecapInput.HRVReading {
        return RecapInput.HRVReading(date: night.start.addingTimeInterval(3 * 3600), sdnn: sdnn)
    }

    func event(_ id: String, _ title: String?, _ start: String, _ end: String, people: Int) -> RecapInput.Event {
        return RecapInput.Event(id: id, title: title, start: at(start), end: at(end), people: people)
    }

    func workout(_ start: String, _ end: String, _ kind: String) -> RecapInput.Workout {
        return RecapInput.Workout(start: at(start), end: at(end), kind: kind)
    }

    func exercise(_ start: String, _ end: String) -> RecapInput.Interval {
        return RecapInput.Interval(start: at(start), end: at(end))
    }

    func calmest(_ time: String, _ bpm: Int) -> DayRecap.Calmest {
        return DayRecap.Calmest(at: at(time), bpm: bpm)
    }

    func caffeine(_ time: String, _ mg: Double) -> RecapInput.Caffeine {
        return RecapInput.Caffeine(date: at(time), mg: mg)
    }
}

private let footer988 = "If today was heavier than a recap can hold: call or text 988, any time. It's for anyone, not only emergencies."

/// The fixture inputs, shared by the golden tests and the banned-word sweep.
private enum Fixtures {
    static let all: [(id: String, build: () -> RecapInput)] = [
        ("01-meeting-survivor", meetingSurvivor), ("02-zen-master", zenMaster), ("03-cardio-only", cardioOnly),
        ("04-running-on-fumes", runningOnFumes), ("05-night-shift", nightShift), ("06-slow-burner", slowBurner),
        ("07-frayed", frayed), ("08-watch-not-worn", watchNotWorn), ("09-first-day-no-baseline", firstDay),
        ("10-partial-day-13:30", { partialDay(at: "13:30") }), ("10-partial-day-20:00", { partialDay(at: "20:00") })
    ]

    static func meetingSurvivor() -> RecapInput {
        let d = Day("2026-09-22")
        var i = d.input(generatedAt: "20:02", resting: 62, coverage: 0.92, awake: 13.0)
        let night = d.night("23:20", "06:50", asleep: 425, awake: 25, awakenings: 2, lowHR: 51)
        i.night = night
        i.hrv = [d.hrv(44, in: night)]
        i.hrvBaseline = 46
        i.sleepWeekMeanHours = 6.9
        i.recoveryMedian7d = 14
        i.recoveryBest7d = RecapInput.RecoveryBest(weekday: "Sunday", minutes: 9)
        i.calendarAccess = RecapInput.CalendarAccess(access: true, showTitles: true, events: [
            d.event("q3", "Q3 planning", "09:00", "10:00", people: 5),
            d.event("one", "1:1", "11:30", "12:00", people: 1),
            d.event("design", "Design review", "14:00", "15:00", people: 8)
        ])
        i.workouts = [d.workout("18:00", "18:40", "running")]
        i.runs = [
            d.run("a", "09:05", "09:30", peakAt: "09:15", peak: 108, stepsPad: 8, recoveredAt: "09:35", tag: .meeting),
            d.run("b", "11:40", "11:55", peakAt: "11:45", peak: 96, stepsPad: 4, recoveredAt: "11:58"),
            d.run("c", "12:35", "12:50", peakAt: "12:42", peak: 99, stepsPad: 310, motion: .active),
            d.run("d", "14:00", "14:40", peakAt: "14:10", peak: 112, stepsPad: 6, recoveredAt: "14:48", tag: .deadline),
            d.run("e", "16:20", "16:30", peakAt: "16:25", peak: 92, stepsPad: 2, recoveredAt: "16:37"),
            d.run("f", "18:05", "18:40", peakAt: "18:30", peak: 171)
        ]
        i.calmest = d.calmest("15:35", 58)
        return i
    }

    static func zenMaster() -> RecapInput {
        let d = Day("2026-09-20")
        var i = d.input(resting: 58, coverage: 0.88, awake: 14.0)
        let night = d.night("23:05", "07:20", asleep: 482, awake: 12, awakenings: 1, lowHR: 47)
        i.night = night
        i.hrv = [d.hrv(62, in: night)]
        i.hrvBaseline = 55
        i.sleepWeekMeanHours = 7.4
        i.runs = [d.run("a", "10:10", "10:40", peakAt: "10:25", peak: 101, stepsPad: 1400, motion: .active)]
        i.calmest = d.calmest("17:50", 54)
        return i
    }

    static func cardioOnly() -> RecapInput {
        let d = Day("2026-09-19")
        var i = d.input(resting: 60, coverage: 0.9, awake: 13.5)
        let night = d.night("23:40", "07:10", asleep: 440, awake: 10, awakenings: 1, lowHR: 49)
        i.night = night
        i.hrv = [d.hrv(50, in: night)]
        i.hrvBaseline = 49
        i.sleepWeekMeanHours = 7.1
        i.recoveryMedian7d = 11
        i.workouts = [d.workout("07:00", "07:55", "cycling")]
        i.exercise = [d.exercise("07:00", "07:55")]
        i.activeEnergyKcal = 610
        i.runs = [
            d.run("w", "07:00", "07:55", peak: 162),
            d.run("a", "13:05", "13:12", peakAt: "13:08", peak: 90, stepsPad: 3, recoveredAt: "13:17")
        ]
        i.calmest = d.calmest("21:10", 55)
        return i
    }

    static func runningOnFumes() -> RecapInput {
        let d = Day("2026-09-23")
        var i = d.input(resting: 64, coverage: 0.86, awake: 13.0)
        let night = d.night("01:40", "06:10", asleep: 245, awake: 25, awakenings: 3, lowHR: 55)
        i.night = night
        i.hrv = [d.hrv(36, in: night)]
        i.hrvBaseline = 48
        i.sleepWeekMeanHours = 6.6
        i.recoveryMedian7d = 12
        i.runs = [
            d.run("a", "10:30", "10:40", peakAt: "10:35", peak: 95, stepsPad: 12, recoveredAt: "10:44"),
            d.run("b", "15:10", "15:25", peakAt: "15:15", peak: 100, stepsPad: 5, recoveredAt: "15:26")
        ]
        i.calmest = d.calmest("12:20", 61)
        return i
    }

    static func nightShift() -> RecapInput {
        let d = Day("2026-09-21")
        var i = d.input(resting: 61, coverage: 0.9, awake: 12.5)
        let night = d.night("23:00", "07:00", asleep: 365, awake: 55, awakenings: 4, lowHR: 50)
        i.night = night
        i.hrv = [d.hrv(40, in: night)]
        i.hrvBaseline = 47
        i.sleepWeekMeanHours = 7.1
        i.recoveryMedian7d = 13
        i.calendarAccess = RecapInput.CalendarAccess(access: true, showTitles: false, events: [
            d.event("sync", "Team sync", "11:00", "11:30", people: 6)
        ])
        i.runs = [
            d.run("n1", "02:50", "03:05", peakAt: "02:55", peak: 98, stage: .awake),
            d.run("n2", "04:30", "04:40", peakAt: "04:35", peak: 94, stage: .rem),
            d.run("a", "11:00", "11:10", peakAt: "11:05", peak: 92, stepsPad: 6, recoveredAt: "11:16")
        ]
        i.calmest = d.calmest("16:40", 57)
        return i
    }

    static func slowBurner() -> RecapInput {
        let d = Day("2026-09-17")
        var i = d.input(resting: 63, coverage: 0.9, awake: 13.0)
        let night = d.night("23:30", "06:40", asleep: 410, awake: 20, awakenings: 2, lowHR: 52)
        i.night = night
        i.hrv = [d.hrv(45, in: night)]
        i.hrvBaseline = 46
        i.sleepWeekMeanHours = 7.0
        i.recoveryMedian7d = 12
        i.calendarAccess = RecapInput.CalendarAccess(access: true, showTitles: true, events: [
            d.event("focus", "Focus time", "13:00", "15:00", people: 0)
        ])
        i.runs = [
            d.run("a", "13:10", "14:25", peakAt: "13:40", peak: 97, stepsPad: 15, recoveredAt: "14:33"),
            d.run("b", "17:00", "17:10", peakAt: "17:05", peak: 96, stepsPad: 3, recoveredAt: "17:14")
        ]
        i.calmest = d.calmest("10:15", 59)
        return i
    }

    static func frayed() -> RecapInput {
        let d = Day("2026-09-24")
        var i = d.input(generatedAt: "20:01", resting: 62, coverage: 0.94, awake: 14.0)
        let night = d.night("00:50", "06:30", asleep: 330, awake: 40, awakenings: 3, lowHR: 54)
        i.night = night
        i.hrv = [d.hrv(33, in: night)]
        i.hrvBaseline = 47
        i.sleepWeekMeanHours = 6.4
        i.recoveryMedian7d = 15
        i.calendarAccess = RecapInput.CalendarAccess(access: true, showTitles: false, events: [
            d.event("e1", nil, "08:30", "09:00", people: 3),
            d.event("e2", nil, "10:00", "11:00", people: 6),
            d.event("e3", nil, "14:30", "15:30", people: 2),
            d.event("e4", nil, "16:00", "16:30", people: 1)
        ])
        i.runs = [
            d.run("n1", "03:10", "03:20", peakAt: "03:15", peak: 97, stage: .awake),
            d.run("a", "08:40", "09:00", peakAt: "08:50", peak: 102, stepsPad: 9, recoveredAt: "09:12"),
            d.run("b", "10:00", "10:35", peakAt: "10:20", peak: 114, stepsPad: 4, recoveredAt: "10:51", tag: .deadline),
            d.run("c", "12:10", "12:20", peakAt: "12:15", peak: 100, stepsPad: 11, recoveredAt: "12:33"),
            d.run("d", "14:30", "15:05", peakAt: "14:45", peak: 123, stepsPad: 2, recoveredAt: "15:25", tag: .panic),
            d.run("e", "16:15", "16:35", peakAt: "16:25", peak: 107, stepsPad: 7, recoveredAt: "16:50"),
            d.run("f", "19:00", "19:10", peakAt: "19:05", peak: 97, stepsPad: 3, recoveredAt: "19:20")
        ]
        i.calmest = d.calmest("13:40", 66)
        return i
    }

    static func watchNotWorn() -> RecapInput {
        let d = Day("2026-09-18")
        var i = d.input(resting: 62, coverage: 0.0, awake: 0)
        i.coverageYesterday = 0.85
        i.hrvBaseline = 46
        i.calendarAccess = RecapInput.CalendarAccess(access: true, showTitles: true, events: [
            d.event("all", "All hands", "10:00", "11:00", people: 40)
        ])
        return i
    }

    static func firstDay() -> RecapInput {
        let d = Day("2026-09-25")
        var i = d.input(resting: 59, coverage: 0.8, awake: 11.0)
        i.baselineNights = 2
        i.recapDays = 0
        let night = d.night("23:50", "06:40", asleep: 400, awake: 10, awakenings: 1, lowHR: 50)
        i.night = night
        i.hrv = [d.hrv(51, in: night)]
        i.runs = [
            d.run("a", "09:20", "09:30", peakAt: "09:25", peak: 89, stepsPad: 5, recoveredAt: "09:32"),
            d.run("b", "13:00", "13:15", peakAt: "13:05", peak: 103, stepsPad: 9, recoveredAt: "13:11"),
            d.run("c", "17:40", "17:50", peakAt: "17:45", peak: 87, stepsPad: 14, recoveredAt: "17:54")
        ]
        i.calmest = d.calmest("11:10", 56)
        return i
    }

    static func partialDay(at generatedAt: String) -> RecapInput {
        let d = Day("2026-09-16")
        let evening = generatedAt == "20:00"
        var i = d.input(generatedAt: generatedAt, resting: 60, coverage: evening ? 0.91 : 0.9, awake: evening ? 13.0 : 6.5)
        let night = d.night("23:30", "06:45", asleep: 432, awake: 8, awakenings: 1, lowHR: 49)
        i.night = night
        i.hrv = [d.hrv(46, in: night)]
        i.hrvBaseline = 47
        i.sleepWeekMeanHours = 7.0
        i.recoveryMedian7d = 12
        i.caffeine = [d.caffeine("08:10", 95), d.caffeine("11:00", 120)]
        i.runs = [
            d.run("a", "08:40", "08:50", peakAt: "08:45", peak: 91, stepsPad: 6, recoveredAt: "08:53"),
            d.run("b", "11:35", "11:45", peakAt: "11:40", peak: 93, stepsPad: 4, recoveredAt: "11:51")
        ]
        if evening {
            i.runs.append(d.run("c", "15:30", "15:45", peakAt: "15:35", peak: 89, stepsPad: 8, recoveredAt: "15:49"))
            i.runs.append(d.run("w", "18:00", "18:30", peak: 158))
            i.workouts = [d.workout("18:00", "18:30", "strength")]
        }
        return i
    }
}

final class RecapTests: XCTestCase {

    private func gen(_ input: RecapInput, picker: RecapCopy.Picker = .first) -> DayRecap {
        return RecapEngine.generate(input, calendar: RFx.calendar, picker: picker)
    }

    private func buckets(_ r: DayRecap) -> [String: DayRecap.Bucket] {
        return Dictionary(uniqueKeysWithValues: r.spikes.map { ($0.id, $0.bucket) })
    }

    private func stillMagnitudes(_ r: DayRecap) -> [String: Int] {
        return Dictionary(uniqueKeysWithValues: r.stillSpikes.map { ($0.id, $0.magnitude) })
    }

    private func recoveries(_ r: DayRecap) -> [String: Int] {
        var out: [String: Int] = [:]
        for s in r.stillSpikes {
            if let m = s.recoveryMinutes {
                out[s.id] = m
            }
        }
        return out
    }

    private func labelled(_ r: DayRecap) -> [String] {
        return r.text.labelled.map { $0.text }
    }

    private func assertLoad(_ r: DayRecap, s: Double, h: Double?, d: Double?, total: Int, band: DayRecap.LoadBand,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let load = r.load else {
            XCTFail("no load", file: file, line: line)
            return
        }
        XCTAssertEqual(load.s, s, accuracy: 0.05, file: file, line: line)
        if let h = h {
            XCTAssertEqual(load.h ?? -1, h, accuracy: 0.05, file: file, line: line)
        } else {
            XCTAssertNil(load.h, file: file, line: line)
        }
        if let d = d {
            XCTAssertEqual(load.d ?? -1, d, accuracy: 0.05, file: file, line: line)
        } else {
            XCTAssertNil(load.d, file: file, line: line)
        }
        XCTAssertEqual(load.total, total, file: file, line: line)
        XCTAssertEqual(load.band, band, file: file, line: line)
    }

    // MARK: Golden days (RECAP 7)

    func testFixture01MeetingSurvivor() {
        let r = gen(Fixtures.meetingSurvivor())
        XCTAssertEqual(buckets(r), ["a": .still, "b": .still, "c": .moving, "d": .still, "e": .still, "f": .workout])
        XCTAssertEqual(r.counts.daytime, 6)
        XCTAssertEqual(r.counts.still, 4)
        XCTAssertEqual(r.counts.noticed, 2)
        XCTAssertEqual(stillMagnitudes(r), ["a": 46, "b": 34, "d": 50, "e": 30])
        XCTAssertEqual(recoveries(r), ["a": 20, "b": 13, "d": 38, "e": 12])
        XCTAssertEqual(r.recovery?.median, 16.5)
        assertLoad(r, s: 40.0, h: 3.6, d: 0.4, total: 44, band: .loaded)
        XCTAssertEqual(r.type, .meetingSurvivor)
        XCTAssertEqual(r.typeStatus, .awarded)
        XCTAssertEqual(r.addOns, [])
        XCTAssertEqual(r.text.headline, "Your heart spiked 6 times today. 4 of them while you were sitting still.")
        XCTAssertEqual(r.text.attribution, "1 in workouts · 1 while moving · 4 sitting still")
        XCTAssertEqual(labelled(r), [
            "'Design review' (8 people): peak 112 bpm. Your body left 12 min before you did. You called it Deadline.",
            "'Q3 planning' (5 people): peak 108 bpm. Your body left 25 min before you did. You called it Meeting.",
            "'1:1' (one-to-one): peak 96 bpm, and came down about when it ended."
        ])
        XCTAssertNil(r.text.calendarHint)
        XCTAssertEqual(r.text.calmest, "Calmest: about 3:35 pm, 58 bpm. Whatever that was, do it again.")
        XCTAssertEqual(r.text.recovery, "Bounced back in about 17 min on average; Sunday was 9.")
        XCTAssertEqual(r.text.lastNight, "Last night: 7 h 05 m asleep, 2 wake-ups the Watch caught, lowest 51 bpm.")
        XCTAssertEqual(r.suggestion?.rule, .breathing)
        XCTAssertEqual(r.suggestion?.source?.citation, "Balban et al. 2023")
        XCTAssertEqual(r.text.shareLine1, "Meeting survivor. Attended everything. Survived everything. Calendar has receipts.")
        XCTAssertEqual(r.text.shareLine2, "6 spikes · about 17 min to come down")
        XCTAssertEqual(r.text.footer, footer988)
        XCTAssertFalse(r.text.footerUnderHeadline)
        XCTAssertEqual(r.text.updated, "updated 8:02 pm")
        XCTAssertNil(r.text.typeSuffix)
    }

    func testFixture01TitlesOffAndSeededVariants() {
        var input = Fixtures.meetingSurvivor()
        input.calendarAccess.showTitles = false
        let r = gen(input)
        XCTAssertEqual(labelled(r)[2], "A one-to-one at about 11:40 am: peak 96 bpm, and came down about when it ended.")

        // Variant 3 of the headline counts tags, never what the user felt.
        let v3 = gen(Fixtures.meetingSurvivor(), picker: .fixed(2))
        XCTAssertEqual(v3.text.headline, "Your heart went up 6 times today. You put a name on 2 of them.")
        let v2 = gen(Fixtures.meetingSurvivor(), picker: .fixed(1))
        XCTAssertEqual(v2.text.headline, "6 spikes. 4 of them from a chair, which is harder than it sounds.")
        XCTAssertEqual(v2.text.attribution, "Workouts 1 · moving 1 · sitting still 4")
    }

    func testFixture02ZenMaster() {
        let r = gen(Fixtures.zenMaster())
        XCTAssertEqual(buckets(r), ["a": .moving])
        XCTAssertEqual(r.counts.daytime, 1)
        XCTAssertEqual(r.counts.still, 0)
        assertLoad(r, s: 0, h: 0, d: 0, total: 0, band: .light)
        XCTAssertEqual(r.type, .zenMaster)
        XCTAssertEqual(r.text.headline, "One spike, on purpose.")
        XCTAssertEqual(r.text.attribution, "1 while moving")
        XCTAssertEqual(labelled(r), [])
        XCTAssertNil(r.recovery)
        XCTAssertNil(r.text.recovery)
        XCTAssertEqual(r.text.calmest, "Calmest: about 5:50 pm, 54 bpm. Whatever that was, do it again.")
        XCTAssertEqual(r.text.lastNight, "Last night: 8 h 02 m asleep, 1 wake-up the Watch caught, lowest 47 bpm.")
        XCTAssertEqual(r.suggestion?.rule, .noNotes)
        XCTAssertEqual(r.suggestion?.text, "No notes. Keep whatever that was.")
        XCTAssertEqual(r.text.shareLine1, "Zen master. A full day of readings and not one spike. We checked twice.")
        XCTAssertEqual(r.text.shareLine2, "Load 0 · slept 8 h 02 m")
        XCTAssertEqual(r.lastNight?.hrvState, .higher)
    }

    func testFixture03CardioOnly() {
        let r = gen(Fixtures.cardioOnly())
        XCTAssertEqual(buckets(r), ["w": .workout, "a": .still])
        XCTAssertEqual(r.counts.daytime, 2)
        XCTAssertEqual(r.counts.still, 1)
        XCTAssertEqual(stillMagnitudes(r), ["a": 30])
        XCTAssertEqual(recoveries(r), ["a": 9])
        XCTAssertEqual(r.recovery?.median, 9)
        XCTAssertEqual(r.recovery?.vsWeek, .aboutTheSame)
        assertLoad(r, s: 7.5, h: 0, d: 0, total: 8, band: .light)
        XCTAssertEqual(r.type, .cardioOnly)
        XCTAssertEqual(r.text.headline, "Your heart spiked 2 times today. One of them while you were sitting still.")
        XCTAssertEqual(r.text.attribution, "1 in workouts · 1 sitting still")
        XCTAssertEqual(labelled(r), ["About 1:05 pm: peak 90 bpm, 7 min. You'd know better than us what that was."])
        XCTAssertEqual(r.text.recovery, "About 9 min from peak back to normal. Your week says 11.")
        XCTAssertEqual(r.suggestion?.rule, .cardioOnly)
        XCTAssertEqual(r.suggestion?.text, "Same again tomorrow, if you like.")
        XCTAssertNil(r.suggestion?.source)
        XCTAssertEqual(r.text.shareLine1, "Cardio only. Your heart only went up when you told it to.")
        XCTAssertEqual(r.text.shareLine2, "2 spikes · about 9 min to come down")
    }

    func testFixture04RunningOnFumes() {
        let r = gen(Fixtures.runningOnFumes())
        XCTAssertEqual(buckets(r), ["a": .still, "b": .still])
        XCTAssertEqual(r.counts.daytime, 2)
        XCTAssertEqual(stillMagnitudes(r), ["a": 31, "b": 36])
        XCTAssertEqual(recoveries(r), ["a": 9, "b": 11])
        XCTAssertEqual(r.recovery?.median, 10)
        assertLoad(r, s: 16.75, h: 20.8, d: 25, total: 63, band: .heavy)
        XCTAssertEqual(r.type, .runningOnFumes)
        XCTAssertEqual(r.text.headline, "Your heart spiked 2 times today. Both of them sitting still.")
        XCTAssertEqual(r.text.lastNight, "Last night: 4 h 05 m asleep, 3 wake-ups the Watch caught, lowest 55 bpm. Short one.")
        XCTAssertEqual(r.lastNight?.hrvState, .lower)
        XCTAssertEqual(r.suggestion?.rule, .earlierBed)
        XCTAssertEqual(r.suggestion?.text, "An earlier bed tonight, if it's on offer. Not a target, just the one thing on the list.")
        XCTAssertEqual(r.suggestion?.source?.citation, "Watson et al. 2015")
        XCTAssertEqual(r.text.shareLine1, "Running on fumes. Ran the whole day on 4 h 05 m. Impressive. The night owes you one.")
        XCTAssertEqual(r.text.shareLine2, "2 spikes · about 10 min to come down")
    }

    func testFixture05NightShift() {
        let r = gen(Fixtures.nightShift())
        XCTAssertEqual(buckets(r), ["n1": .inBed, "n2": .inBed, "a": .still])
        XCTAssertEqual(r.counts.inBedAwake, 1)
        XCTAssertEqual(r.counts.inBedAsleep, 1)
        XCTAssertEqual(r.counts.daytime, 1)
        XCTAssertEqual(r.counts.still, 1)
        assertLoad(r, s: 7.75, h: 12.4, d: 7.64, total: 28, band: .moderate)
        XCTAssertEqual(r.type, .nightShift)
        XCTAssertEqual(r.text.headline, "Your heart spiked once today, sitting still.")
        XCTAssertEqual(labelled(r), ["A 6-person meeting at about 11:00 am: peak 92 bpm. Your body left 14 min before you did."])
        XCTAssertEqual(r.text.lastNight, "Last night: 6 h 05 m asleep, 4 wake-ups the Watch caught, lowest 50 bpm. Your heart went up once while you were awake in bed, around 2:55 am. One rise around 4:35 am while you were asleep. Dreams do that too.")
        XCTAssertEqual(r.suggestion?.rule, .nothingToFix)
        XCTAssertEqual(r.suggestion?.text, "Nothing to fix. Read it, close it, go do something else.")
        XCTAssertEqual(r.text.shareLine1, "Night shift. Your heart worked a night shift. Nobody asked it to.")
        XCTAssertEqual(r.text.shareLine2, "1 spike · about 11 min to come down")
    }

    func testFixture06SlowBurner() {
        let r = gen(Fixtures.slowBurner())
        XCTAssertEqual(buckets(r), ["a": .still, "b": .still])
        let a = r.spikes.first { $0.id == "a" }
        XCTAssertEqual(a?.stepDensity ?? 0, 1.8, accuracy: 0.05)
        XCTAssertEqual(stillMagnitudes(r), ["a": 34, "b": 33])
        XCTAssertEqual(recoveries(r), ["a": 53, "b": 9])
        XCTAssertEqual(r.recovery?.median, 31)
        assertLoad(r, s: 16.75, h: 1.8, d: 1.4, total: 20, band: .light)
        XCTAssertEqual(r.type, .slowBurner)
        XCTAssertEqual(labelled(r), [
            "'Focus time' (solo): peak 97 bpm, and came down about when it ended.",
            "About 5:05 pm: peak 96 bpm, 10 min. You'd know better than us what that was."
        ])
        XCTAssertEqual(r.text.labelled[0].stretch, "a long stretch, 1 h 15 m")
        XCTAssertNil(r.text.labelled[1].stretch)
        XCTAssertEqual(a?.label?.relation, .leftBefore)
        XCTAssertEqual(r.text.recovery, "About 31 min from peak back to normal. Your week says 12.")
        XCTAssertEqual(r.recovery?.vsWeek, .slower)
        XCTAssertEqual(r.suggestion?.rule, .walk)
        XCTAssertEqual(r.suggestion?.text, "A short walk after the next one. One bout of movement takes the edge off a little, on average. A little is fine.")
        XCTAssertEqual(r.suggestion?.source?.citation, "Ensari et al. 2015")
        XCTAssertEqual(r.text.shareLine1, "Slow burner. Nothing dramatic. Just on, for a while. Like a porch light.")
        XCTAssertEqual(r.text.shareLine2, "2 spikes · about 31 min to come down")
    }

    func testFixture07Frayed() {
        let r = gen(Fixtures.frayed())
        XCTAssertEqual(r.counts.daytime, 6)
        XCTAssertEqual(r.counts.still, 6)
        XCTAssertEqual(r.counts.noticed, 2)
        XCTAssertEqual(r.counts.inBedAwake, 1)
        XCTAssertEqual(r.counts.inBedAsleep, 0)
        XCTAssertEqual(stillMagnitudes(r), ["a": 40, "b": 52, "c": 38, "d": 61, "e": 45, "f": 35])
        XCTAssertEqual(recoveries(r), ["a": 22, "b": 31, "c": 18, "d": 40, "e": 25, "f": 15])
        XCTAssertEqual(r.recovery?.median, 23.5)
        assertLoad(r, s: 50, h: 24.8, d: 15, total: 90, band: .runningHot)
        XCTAssertEqual(r.type, .frayed)
        XCTAssertEqual(r.text.headline, "Your heart spiked 6 times today. All of them sitting still.")
        XCTAssertEqual(labelled(r), [
            "A 2-person meeting at about 2:30 pm: peak 123 bpm, and came down about when it ended. You called it Panic.",
            "A 6-person meeting at about 10:00 am: peak 114 bpm, and came down about when it ended. You called it Deadline.",
            "A one-to-one at about 4:15 pm: peak 107 bpm, hung around 20 min after it ended."
        ])
        XCTAssertFalse(r.text.footerUnderHeadline)
        XCTAssertEqual(r.text.lastNight, "Last night: 5 h 30 m asleep, 3 wake-ups the Watch caught, lowest 54 bpm. Your heart went up once while you were awake in bed, around 3:15 am. Short one.")
        XCTAssertEqual(r.suggestion?.rule, .breathing)
        XCTAssertEqual(r.suggestion?.source?.citation, "Balban et al. 2023")
        XCTAssertEqual(r.text.shareLine1, "Frayed. Everything, all at once. Tomorrow is allowed to be smaller.")
        XCTAssertEqual(r.text.shareLine2, "6 spikes · about 24 min to come down")
        XCTAssertFalse(r.text.shareLine1?.hasSuffix("Frayed") ?? true)
    }

    func testFixture08WatchNotWorn() {
        let input = Fixtures.watchNotWorn()
        let r = gen(input)
        XCTAssertEqual(r.typeStatus, .notWorn)
        XCTAssertNil(r.type)
        XCTAssertNil(r.load)
        XCTAssertNil(r.recovery)
        XCTAssertNil(r.suggestion)
        XCTAssertNil(r.text.shareLine1)
        XCTAssertEqual(r.counts, .zero)
        XCTAssertEqual(r.text.blocks, [
            "No Watch data today. Nothing to recap, nothing to read into it.",
            "No sleep data: the Watch was off the wrist or under 30 % (Apple's rule, not ours).",
            footer988
        ])
        XCTAssertFalse(r.text.blocks.joined().contains("All hands"))

        let decision = RecapNotification.decision(
            coverageToday: 0, coverageYesterday: 0.85, date: input.recapTime, calendar: RFx.calendar,
            nudgedThisWeek: false, picker: .first
        )
        XCTAssertEqual(decision, .send(body: "Not much Watch time today. There's still a recap, a short one."))
    }

    func testFixture09FirstDayNoBaseline() {
        let r = gen(Fixtures.firstDay())
        XCTAssertEqual(r.counts.daytime, 3)
        XCTAssertEqual(r.counts.still, 3)
        XCTAssertEqual(stillMagnitudes(r), ["a": 30, "b": 44, "c": 28])
        XCTAssertEqual(recoveries(r), ["a": 7, "b": 6, "c": 9])
        XCTAssertEqual(r.recovery?.median, 7)
        assertLoad(r, s: 25.5, h: nil, d: 2.8, total: 38, band: .moderate)
        XCTAssertEqual(r.text.loadLabel, "first week")
        XCTAssertTrue(r.firstWeek)
        XCTAssertEqual(r.type, .bouncedBack)
        XCTAssertEqual(r.text.headline, "Your heart spiked 3 times today. All of them sitting still.")
        XCTAssertEqual(labelled(r), [
            "About 1:05 pm: peak 103 bpm, 15 min. You'd know better than us what that was.",
            "About 9:25 am: peak 89 bpm, 10 min. You'd know better than us what that was.",
            "About 5:45 pm: peak 87 bpm, 10 min. You'd know better than us what that was."
        ])
        XCTAssertEqual(r.text.calendarHint, "Turn on calendar labels to see which of these had an invite.")
        XCTAssertEqual(r.text.recovery, "About 7 min from peak back to normal. We'll have a comparison in a few days.")
        XCTAssertEqual(r.text.lastNight, "Last night: 6 h 40 m asleep, 1 wake-up the Watch caught, lowest 50 bpm.")
        XCTAssertEqual(r.lastNight?.hrvState, .noBaseline)
        XCTAssertEqual(r.text.loadNotes, ["First week: baselines fill in as we go."])
        XCTAssertEqual(r.suggestion?.rule, .breathing)
        XCTAssertEqual(r.text.shareLine1, "Bounced back. Spiked, sure. Never stayed.")
        XCTAssertEqual(r.text.shareLine2, "3 spikes · about 7 min to come down")
    }

    func testFixture10PartialDayThenRegenerated() {
        let early = gen(Fixtures.partialDay(at: "13:30"))
        XCTAssertEqual(early.counts.daytime, 2)
        XCTAssertEqual(early.counts.still, 2)
        XCTAssertEqual(early.typeStatus, .pending)
        XCTAssertNil(early.type)
        XCTAssertEqual(early.text.typeLabel, "Type at 8 pm")
        XCTAssertNil(early.text.typeOneLiner)
        assertLoad(early, s: 16.0, h: 1.8, d: 0, total: 18, band: .light)
        XCTAssertEqual(early.text.loadLabel, "so far")
        XCTAssertEqual(early.addOns, [.caffeineCurve])
        XCTAssertEqual(early.text.addOns, ["+ Caffeine curve"])
        XCTAssertEqual(early.text.headline, "Your heart spiked 2 times so far. Both of them sitting still.")
        XCTAssertNil(early.text.updated)
        XCTAssertNil(early.text.shareLine1)

        let late = gen(Fixtures.partialDay(at: "20:00"))
        XCTAssertEqual(late.counts.daytime, 4)
        XCTAssertEqual(late.counts.still, 3)
        XCTAssertEqual(stillMagnitudes(late), ["a": 31, "b": 33, "c": 29])
        XCTAssertEqual(recoveries(late), ["a": 8, "b": 11, "c": 14])
        XCTAssertEqual(late.recovery?.median, 11)
        assertLoad(late, s: 23.25, h: 1.8, d: 0, total: 25, band: .moderate)
        XCTAssertNil(late.text.loadLabel)
        XCTAssertEqual(late.type, .justAWeekday)
        XCTAssertEqual(late.text.typeLabel, "Just a Wednesday")
        XCTAssertEqual(late.addOns, [.caffeineCurve])
        XCTAssertEqual(late.text.headline, "Your heart spiked 4 times today. 3 of them while you were sitting still.")
        XCTAssertEqual(late.text.attribution, "1 in workouts · 3 sitting still")
        XCTAssertEqual(late.text.shareLine1, "Just a Wednesday. 4 spikes, none of them a story.")
        XCTAssertEqual(late.text.shareLine2, "Load 25 · slept 7 h 12 m")

        // Same user, same day: the seed and every variant hold across openings.
        let seeded = RecapCopy.Picker.seeded(userId: "user-1", dayKey: "2026-09-16")
        let a = gen(Fixtures.partialDay(at: "13:30"), picker: seeded)
        let b = gen(Fixtures.partialDay(at: "20:00"), picker: seeded)
        XCTAssertEqual(a.seed, b.seed)
        XCTAssertEqual(a.text.lastNight, b.text.lastNight)
        XCTAssertEqual(a.text.calmest, b.text.calmest)
        XCTAssertNotEqual(seeded.seed, RecapCopy.Picker.seeded(userId: "user-1", dayKey: "2026-09-17").seed)
    }
}

// MARK: Banned words (RECAP 0.1) and the parts behind the fixtures

extension RecapTests {

    func testNoTemplateContainsABannedWord() {
        XCTAssertGreaterThan(RecapCopy.allTemplates.count, 60)
        for template in RecapCopy.allTemplates {
            XCTAssertNil(RecapCopy.bannedWord(in: template), template)
        }
    }

    func testNoRenderedFixtureContainsABannedWordInAnyVariant() {
        for fixture in Fixtures.all {
            for index in 0..<4 {
                let r = RecapEngine.generate(fixture.build(), calendar: RFx.calendar, picker: .fixed(index))
                var strings = r.text.blocks + r.text.loadNotes + r.text.addOns
                strings += r.text.labelled.compactMap { $0.stretch }
                strings += [r.text.typeOneLiner, r.text.typeSuffix, r.text.loadLabel, r.text.updated,
                            r.text.shareLine1, r.text.shareLine2, r.text.suggestionSource].compactMap { $0 }
                for s in strings {
                    XCTAssertNil(RecapCopy.bannedWord(in: s), "\(fixture.id) variant \(index): \(s)")
                    XCTAssertFalse(s.contains("!"), "\(fixture.id): \(s)")
                    XCTAssertFalse(s.lowercased().contains("you should"), "\(fixture.id): \(s)")
                }
            }
        }
    }

    func testBannedWordMatcherCatchesEveryFormAndLeavesTheUsersWord() {
        XCTAssertEqual(RecapCopy.bannedWord(in: "A Panic Attack"), "panic attack")
        XCTAssertEqual(RecapCopy.bannedWord(in: "no diagnosis here"), "diagnos")
        XCTAssertEqual(RecapCopy.bannedWord(in: "under stress"), "stress")
        XCTAssertNil(RecapCopy.bannedWord(in: "You called it Panic."))
        XCTAssertTrue(RecapCopy.allowedUserWords.contains("Panic"))
        XCTAssertEqual(RecapCopy.allowedUserWords.count, 8)
    }

    func testDayTypePriorityAndPartition() {
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 5, load: 65)), .frayed)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 5, load: 64, awakeInBedSpikes: 2)), .nightShift)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 4, awakeInBedSpikes: 1, wasoMinutes: 45)), .nightShift)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 4, calendarOn: true, meetingSpikes: 2, labelledSpikes: 2)), .meetingSurvivor)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 4, calendarOn: true, meetingSpikes: 2, labelledSpikes: 1)), .justAWeekday)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 4, calendarOn: false, meetingSpikes: 2, labelledSpikes: 4)), .justAWeekday)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 1, hasSimmer: true)), .slowBurner)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 3, stillElevatedMinutes: 90)), .slowBurner)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 2, recoveryMedian: 20)), .slowBurner)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 3, asleepHours: 5.5)), .runningOnFumes)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 4, asleepHours: 5.5)), .justAWeekday)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 2, load: 50, recoveryMedian: 8, allRecoveriesKnown: true, asleepHours: 7)), .bouncedBack)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 2, load: 51, recoveryMedian: 8, allRecoveriesKnown: true, asleepHours: 7)), .justAWeekday)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 0, asleepHours: 7, coverage: 0.7, awakeTrackedHours: 12)), .zenMaster)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 0, asleepHours: 6.9, coverage: 0.7, awakeTrackedHours: 12, hrvNight: 50, hrvBaseline: 50)), .zenMaster)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 0, asleepHours: 6.9, coverage: 0.7, awakeTrackedHours: 12, hrvNight: 49, hrvBaseline: 50)), .quietDay)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 0, asleepHours: 7, coverage: 0.69, awakeTrackedHours: 12, longestWorkoutMinutes: 20)), .cardioOnly)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 1, load: 40, exerciseMinutes: 30)), .cardioOnly)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 1, load: 41, activeEnergyKcal: 500)), .quietDay)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 1)), .quietDay)
        XCTAssertEqual(DayType.classify(DayType.Facts(stillSpikes: 2)), .justAWeekday)
        XCTAssertEqual(DayType.allCases.count, 10)
        XCTAssertEqual(DayType.nightShift.rawValue, "nightShift")
        XCTAssertEqual(DayType.runningOnFumes.rawValue, "runningOnFumes")
    }

    func testPlaceholderFillHandlesPluralsAndCapitals() {
        XCTAssertEqual(RecapCopy.fill("{n} {n:spike|spikes}", ["n": "1"]), "1 spike")
        XCTAssertEqual(RecapCopy.fill("{n} {n:spike|spikes}", ["n": "3"]), "3 spikes")
        XCTAssertEqual(RecapCopy.fill("{Time} was calm", ["time": "about 2:40 pm"]), "About 2:40 pm was calm")
        XCTAssertEqual(RecapCopy.fill("{missing}", [:]), "{missing}")
        XCTAssertEqual(RecapCopy.fill("no braces", [:]), "no braces")
    }

    func testClockFloorsToFiveMinutesAndDurationsRound() {
        let d = Day("2026-09-22")
        XCTAssertEqual(RecapCopy.clock(d.at("13:08"), calendar: RFx.calendar), "1:05 pm")
        XCTAssertEqual(RecapCopy.clock(d.at("00:03"), calendar: RFx.calendar), "12:00 am")
        XCTAssertEqual(RecapCopy.clock(d.at("20:02"), calendar: RFx.calendar, roundToFive: false), "8:02 pm")
        XCTAssertEqual(RecapCopy.about(d.at("15:35"), calendar: RFx.calendar), "about 3:35 pm")
        XCTAssertEqual(RecapCopy.hourClock(d.at("20:30"), calendar: RFx.calendar), "8:30 pm")
        XCTAssertEqual(RecapCopy.duration(0), "a moment")
        XCTAssertEqual(RecapCopy.duration(14), "14 min")
        XCTAssertEqual(RecapCopy.duration(17), "15 min")
        XCTAssertEqual(RecapCopy.duration(18), "20 min")
        XCTAssertEqual(RecapCopy.hoursMinutes(425), "7 h 05 m")
        XCTAssertEqual(RecapCopy.recoveryText(16.5), "about 17 min")
        XCTAssertEqual(RecapCopy.recoveryText(60), "over an hour")
        XCTAssertEqual(RecapCopy.weekday(of: d.at("12:00"), calendar: RFx.calendar), "Tuesday")
    }

    func testRestingHRMedianNewestAndFallback() {
        XCTAssertEqual(RecapEngine.restingHR(history: [60, 70, 62]).value, 62)
        XCTAssertEqual(RecapEngine.restingHR(history: [60, 70]).value, 70)
        let fallback = RecapEngine.restingHR(history: [])
        XCTAssertEqual(fallback.value, 65)
        XCTAssertTrue(fallback.isFallback)

        var input = Fixtures.cardioOnly()
        input.restingHistory = []
        let r = RecapEngine.generate(input, calendar: RFx.calendar, picker: .first)
        XCTAssertTrue(r.restingIsFallback)
        XCTAssertEqual(r.threshold, 90)
        XCTAssertEqual(r.text.loadLabel, "estimated")
        XCTAssertEqual(r.text.loadNotes, ["A full day on the wrist and Apple hands over a resting rate."])
    }

    func testThresholdSuffixPanicFooterAndThinCoverage() {
        var input = Fixtures.frayed()
        input.elevatedMargin = 20
        input.runs[1].tag = .panic
        let r = RecapEngine.generate(input, calendar: RFx.calendar, picker: .first)
        XCTAssertEqual(r.text.typeSuffix, "· threshold +20")
        XCTAssertTrue(r.text.footerUnderHeadline)
        XCTAssertEqual(r.text.blocks[1], footer988)
        XCTAssertEqual(r.text.blocks.last, r.suggestion?.text)

        var thin = Fixtures.frayed()
        thin.coverage = 0.4
        thin.awakeTrackedHours = 5.5
        let t = RecapEngine.generate(thin, calendar: RFx.calendar, picker: .first)
        XCTAssertEqual(t.typeStatus, .thinCoverage)
        XCTAssertNil(t.type)
        XCTAssertEqual(t.text.typeLabel, "Not enough Watch time for a type today")
        XCTAssertEqual(t.text.headline, "Your heart spiked 6 times in the 6 hours the Watch was on.")
        XCTAssertEqual(t.text.loadLabel, "partial")
        XCTAssertNil(t.text.shareLine1)
    }

    func testFooterWithoutANumberNeverPrintsOne() {
        var input = Fixtures.zenMaster()
        input.crisisNumber = nil
        let r = RecapEngine.generate(input, calendar: RFx.calendar, picker: .first)
        XCTAssertEqual(r.text.footer, "If today was heavier than a recap can hold: tap here for a crisis line, any time. It's for anyone, not only emergencies.")
        XCTAssertEqual(r.text.blocks.last, r.text.footer)

        let bare = RecapInput(dayKey: input.dayKey, dayStart: input.dayStart, now: input.now, recapTime: input.recapTime,
                              coverage: 0.9, awakeTrackedHours: 14)
        XCTAssertNil(bare.crisisNumber, "a number is opted into per region by the app layer, never assumed")
    }

    func testSuggestionNeverRunsThreeDaysInARow() {
        var input = Fixtures.meetingSurvivor()
        input.previousSuggestions = [.breathing, .breathing]
        XCTAssertEqual(RecapEngine.generate(input, calendar: RFx.calendar, picker: .first).suggestion?.rule, .meetingSurvivor)
        input.previousSuggestions = [.breathing, .walk]
        XCTAssertEqual(RecapEngine.generate(input, calendar: RFx.calendar, picker: .first).suggestion?.rule, .breathing)
        XCTAssertEqual(RecapEngine.generate(input, calendar: RFx.calendar, picker: .fixed(1)).suggestion?.text,
                       "Two-minute version if five is too many: long exhales, that's the whole trick.")
    }

    func testEarlierBedNumberedVariantOnlyWhenTheGapIsUnderAnHour() {
        var input = Fixtures.runningOnFumes()
        input.night?.asleepMinutes = 375
        input.sleepWeekMeanHours = 6.0
        let r = RecapEngine.generate(input, calendar: RFx.calendar, picker: .first)
        XCTAssertEqual(r.suggestion?.rule, .earlierBed)
        XCTAssertEqual(r.suggestion?.text, "Bed 45 min earlier tonight would put you over 7 hours. That's the whole plan, and it's optional.")
    }

    func testNotificationScheduleBodiesAndSkipRule() {
        XCTAssertEqual(RecapNotification.identifier, "recap-daily")
        XCTAssertEqual(RecapNotification.threadIdentifier, "recap")
        XCTAssertEqual(RecapNotification.title, "Frayed")
        XCTAssertEqual(RecapNotification.bodies.count, 5)
        XCTAssertEqual(RecapNotification.Schedule().dateComponents, DateComponents(hour: 20, minute: 0))
        XCTAssertEqual(RecapNotification.Schedule(hour: 25, minute: -1).hour, 23)
        XCTAssertEqual(RecapNotification.Schedule(hour: 25, minute: -1).minute, 0)
        for body in RecapNotification.bodies {
            XCTAssertNil(RecapCopy.bannedWord(in: body), body)
            XCTAssertFalse(body.contains { $0.isNumber }, body)
        }

        let d = Day("2026-09-20")
        let sunday = d.at("20:00")
        let monday = d.at("20:00", 1)
        let cal = RFx.calendar
        XCTAssertEqual(RecapNotification.decision(coverageToday: 0.5, coverageYesterday: 0, date: monday, calendar: cal, nudgedThisWeek: false, picker: .fixed(3)),
                       .send(body: "Recap's ready. Your heart kept notes."))
        XCTAssertEqual(RecapNotification.decision(coverageToday: 0, coverageYesterday: 0.3, date: monday, calendar: cal, nudgedThisWeek: false, picker: .first),
                       .send(body: RecapNotification.notWornBody))
        XCTAssertEqual(RecapNotification.decision(coverageToday: 0, coverageYesterday: 0, date: monday, calendar: cal, nudgedThisWeek: false, picker: .first), .skip)
        XCTAssertEqual(RecapNotification.decision(coverageToday: 0, coverageYesterday: 0, date: sunday, calendar: cal, nudgedThisWeek: false, picker: .first),
                       .nudge(body: RecapNotification.sundayNudgeBody))
        XCTAssertEqual(RecapNotification.decision(coverageToday: 0, coverageYesterday: 0, date: sunday, calendar: cal, nudgedThisWeek: true, picker: .first), .skip)
        XCTAssertEqual(RecapNotification.decision(coverageToday: 0.9, coverageYesterday: 0.9, healthReadable: false, date: monday, calendar: cal, nudgedThisWeek: false, picker: .first),
                       .send(body: RecapNotification.notWornBody))
        XCTAssertEqual(RecapNotification.Schedule(hour: 20).nextFireDate(after: d.at("20:01"), calendar: cal), monday)
    }

    func testNightFromSamplesGroupsAndCountsAwakenings() {
        let d = Day("2026-09-22")
        let samples: [RecapInput.SleepSample] = [
            RecapInput.SleepSample(start: d.at("23:20", -1), end: d.at("01:00"), stage: .core),
            RecapInput.SleepSample(start: d.at("01:00"), end: d.at("01:03"), stage: .awake),
            RecapInput.SleepSample(start: d.at("01:03"), end: d.at("03:30"), stage: .deep),
            RecapInput.SleepSample(start: d.at("03:30"), end: d.at("03:31"), stage: .awake),
            RecapInput.SleepSample(start: d.at("03:31"), end: d.at("06:50"), stage: .rem),
            RecapInput.SleepSample(start: d.at("13:00"), end: d.at("13:40"), stage: .core)
        ]
        let hr = [
            RecapInput.HeartRateSample(date: d.at("02:00"), bpm: 51),
            RecapInput.HeartRateSample(date: d.at("01:01"), bpm: 70)
        ]
        let night = RecapEngine.night(from: samples, heartRate: hr, dayStart: d.at("04:00"), calendar: RFx.calendar)
        XCTAssertEqual(night?.start, d.at("23:20", -1))
        XCTAssertEqual(night?.end, d.at("06:50"))
        XCTAssertEqual(night?.asleepMinutes, 446)
        XCTAssertEqual(night?.awakeMinutes, 4)
        XCTAssertEqual(night?.awakenings, 1)
        XCTAssertEqual(night?.lowHR, 51)
        XCTAssertNil(RecapEngine.night(from: [], heartRate: [], dayStart: d.at("04:00"), calendar: RFx.calendar))
    }

    func testBeatsKeepTheHighestReadingPerMinuteInsideTheWindow() {
        let d = Day("2026-09-22")
        let hr = [
            RecapInput.HeartRateSample(date: d.at("09:00").addingTimeInterval(50), bpm: 88),
            RecapInput.HeartRateSample(date: d.at("09:00").addingTimeInterval(10), bpm: 95),
            RecapInput.HeartRateSample(date: d.at("09:00").addingTimeInterval(30), bpm: 90),
            RecapInput.HeartRateSample(date: d.at("08:58"), bpm: 70),
            RecapInput.HeartRateSample(date: d.at("03:00"), bpm: 60),
            RecapInput.HeartRateSample(date: d.at("21:00"), bpm: 60)
        ]
        let beats = RecapEngine.beats(from: hr, start: d.at("04:00"), end: d.at("20:00"))
        XCTAssertEqual(beats, [
            DayRecap.Beat(at: d.at("08:58"), bpm: 70),
            DayRecap.Beat(at: d.at("09:00"), bpm: 95)
        ])
    }

    func testCalmestFromReadingsNeedsThreeHoursAndSkipsMotion() {
        let d = Day("2026-09-22")
        var readings: [RecapInput.HeartRateSample] = []
        var t = d.at("08:00")
        while t < d.at("15:00") {
            let calm = t >= d.at("12:00") && t <= d.at("12:10")
            readings.append(RecapInput.HeartRateSample(date: t, bpm: calm ? 55 : 70))
            t = t.addingTimeInterval(300)
        }
        readings.append(RecapInput.HeartRateSample(date: d.at("13:00"), bpm: 40, motion: .active))
        let calm = RecapEngine.calmest(from: readings, night: nil, dayStart: d.at("04:00"), now: d.at("20:00"))
        XCTAssertEqual(calm?.bpm, 55)
        XCTAssertEqual(calm?.at, d.at("12:05"))
        XCTAssertNil(RecapEngine.calmest(from: Array(readings.prefix(10)), night: nil, dayStart: d.at("04:00"), now: d.at("20:00")))
    }

    func testRecoveryFromSamplesAndProportionalSteps() {
        let d = Day("2026-09-22")
        let samples = [
            RecapInput.HeartRateSample(date: d.at("09:15"), bpm: 108),
            RecapInput.HeartRateSample(date: d.at("09:20"), bpm: 95),
            RecapInput.HeartRateSample(date: d.at("09:25"), bpm: 80),
            RecapInput.HeartRateSample(date: d.at("09:30"), bpm: 71),
            RecapInput.HeartRateSample(date: d.at("10:30"), bpm: 60)
        ]
        XCTAssertEqual(RecapEngine.recoveredAt(samples: samples, peakAt: d.at("09:15"), resting: 62), d.at("09:30"))
        XCTAssertNil(RecapEngine.recoveredAt(samples: samples, peakAt: d.at("09:15"), resting: 55))
        let steps = [RecapInput.Steps(start: d.at("09:00"), end: d.at("09:10"), count: 100)]
        XCTAssertEqual(RecapEngine.steps(from: d.at("09:05"), to: d.at("09:30"), samples: steps), 50, accuracy: 0.01)

        var input = Fixtures.cardioOnly()
        input.runs[1].recoveredAt = nil
        input.runs[1].stepsPadded = nil
        input.heartRate = [RecapInput.HeartRateSample(date: d.at("13:17"), bpm: 68)]
        input.steps = [RecapInput.Steps(start: input.runs[1].start, end: input.runs[1].end, count: 40)]
        let r = RecapEngine.generate(input, calendar: RFx.calendar, picker: .first)
        XCTAssertEqual(r.spikes.last?.bucket, .moving)
        XCTAssertNil(r.recovery)
    }

    func testInBedRunsDeriveTheirStageFromSleepSamples() {
        var input = Fixtures.nightShift()
        input.runs[0].stage = nil
        input.runs[1].stage = nil
        let d = Day("2026-09-21")
        input.sleep = [RecapInput.SleepSample(start: d.at("02:52"), end: d.at("03:00"), stage: .awake)]
        let r = RecapEngine.generate(input, calendar: RFx.calendar, picker: .first)
        XCTAssertEqual(r.counts.inBedAwake, 1)
        XCTAssertEqual(r.counts.inBedAsleep, 1)
        XCTAssertEqual(r.type, .nightShift)
    }

    func testRecapRoundTripsThroughJSONWithoutSamplesOrTitlesLeaking() throws {
        let r = RecapEngine.generate(Fixtures.meetingSurvivor(), calendar: RFx.calendar, picker: .first)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(r)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(DayRecap.self, from: data)
        XCTAssertEqual(back.text, r.text)
        XCTAssertEqual(back.counts, r.counts)
        XCTAssertEqual(back.type, .meetingSurvivor)
        XCTAssertEqual(back.spikes.map { $0.id }, ["a", "b", "c", "d", "e", "f"])
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(raw.contains("samples"))
        XCTAssertTrue(raw.contains("Design review"))

        let ledger = r.ledger(day: RFx.calendar.startOfDay(for: r.generatedAt), recapOpened: true)
        XCTAssertTrue(ledger.worn)
        XCTAssertTrue(ledger.tracked)
        XCTAssertEqual(ledger.stillSpikes, 4)
        XCTAssertEqual(ledger.workoutSpikes, 1)
        XCTAssertEqual(ledger.load, 44)
        XCTAssertEqual(ledger.recoveryMedianMinutes, 16.5)
        XCTAssertEqual(ledger.asleepMinutes, 425)
        XCTAssertEqual(ledger.labelledSpikes.count, 3)
        XCTAssertFalse(RecapEngine.generate(Fixtures.watchNotWorn(), calendar: RFx.calendar, picker: .first)
                        .ledger(day: r.generatedAt, recapOpened: false).worn)
    }
}
