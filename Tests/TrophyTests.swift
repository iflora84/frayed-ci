import XCTest
import Foundation

// "Now" is Thursday 2026-09-24 12:00 in America/Los_Angeles; weeks start on
// Monday. Every date goes through an explicit calendar so the runner's zone
// never matters. The fixture is private: Fx in FrayedCoreTests.swift belongs
// to the model tests and builds Moments, which these tests never touch.
private enum TrophyFx {
    static let zone = TimeZone(identifier: "America/Los_Angeles")!

    static func calendar(firstWeekday: Int = 2) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = firstWeekday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar()
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

    static func engine(_ now: String = "2026-09-24 12:00") -> TrophyEngine {
        return TrophyEngine(calendar: calendar(), now: date(now))
    }

    /// A ledger for the local day `ymd` ("2026-09-22"). `bedtime` is a full
    /// "yyyy-MM-dd HH:mm" of the evening before.
    static func day(
        _ ymd: String,
        still: Int = 2,
        moving: Int = 0,
        workout: Int = 0,
        night: Int = 0,
        recovery: Double? = nil,
        load: Int? = nil,
        sleep: Int? = nil,
        asleep: Int? = nil,
        bedtime: String? = nil,
        labelled: [LabelledSpike] = [],
        opened: Bool = true,
        worn: Bool = true,
        tracked: Bool = true
    ) -> DayLedger {
        return DayLedger(
            day: date(ymd + " 00:00"),
            worn: worn,
            tracked: tracked,
            stillSpikes: still,
            movingSpikes: moving,
            workoutSpikes: workout,
            nightRises: night,
            recoveryMedianMinutes: recovery,
            load: load,
            sleepScore: sleep,
            asleepMinutes: asleep,
            bedtime: bedtime.map { date($0) },
            labelledSpikes: labelled,
            recapOpened: opened
        )
    }

    static func days(_ range: ClosedRange<Int>, month: String = "09") -> [DayLedger] {
        return range.map { day(String(format: "2026-\(month)-%02ld", $0)) }
    }
}

final class TrophyTests: XCTestCase {

    private let engine = TrophyFx.engine()

    // MARK: Day trophies

    func testFirstDayEarnsNoRecord() {
        let d = TrophyFx.day("2026-09-20", recovery: 12, load: 30, sleep: 70)
        XCTAssertEqual(engine.dayTrophies(for: d, history: [d]), [])
        XCTAssertEqual(engine.dayTrophies(for: d, history: []), [])
    }

    func testRecordsNeedSomethingToBeat() {
        let history = [
            TrophyFx.day("2026-09-10", recovery: 12, load: 40, sleep: 70),
            TrophyFx.day("2026-09-12", recovery: 9, load: 35, sleep: 75),
            TrophyFx.day("2026-09-30", recovery: 1, load: 1, sleep: 99)
        ]
        let best = TrophyFx.day("2026-09-20", recovery: 8.5, load: 34, sleep: 76)
        XCTAssertEqual(engine.dayTrophies(for: best, history: history + [best]),
                       [.fastestRecovery, .calmestDay, .bestNight], "the future day never counts")

        let tie = TrophyFx.day("2026-09-20", recovery: 9, load: 35, sleep: 75)
        XCTAssertEqual(engine.dayTrophies(for: tie, history: history + [tie]), [])

        let partial = TrophyFx.day("2026-09-20", recovery: 5)
        XCTAssertEqual(engine.dayTrophies(for: partial, history: history + [partial]), [.fastestRecovery])

        let noValues = [TrophyFx.day("2026-09-10")]
        let first = TrophyFx.day("2026-09-20", recovery: 5, load: 10, sleep: 90)
        XCTAssertEqual(engine.dayTrophies(for: first, history: noValues + [first]), [], "the first day with a value sets no record")
    }

    func testBouncedBackNeedsThreeSpikesAndAnEightMinuteMedian() {
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", still: 3, recovery: 8), history: []), [.bouncedBack])
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", still: 2, recovery: 8), history: []), [])
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", still: 4, recovery: 8.5), history: []), [])
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", still: 4, recovery: nil), history: []), [])
        XCTAssertTrue(TrophyEngine.bouncedBack(TrophyFx.day("2026-09-22", still: 5, recovery: 7.5)))
    }

    func testSleptItOffNeedsAHeavyYesterday() {
        let heavy = TrophyFx.day("2026-09-21", load: 60)
        let light = TrophyFx.day("2026-09-21", load: 59)
        let rested = TrophyFx.day("2026-09-22", sleep: 80)
        XCTAssertEqual(engine.dayTrophies(for: rested, history: [heavy, rested]), [.sleptItOff])
        XCTAssertEqual(engine.dayTrophies(for: rested, history: [light, rested]), [])
        XCTAssertEqual(engine.dayTrophies(for: rested, history: [rested]), [])
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", sleep: 79), history: [heavy]), [])

        let twoDaysBefore = TrophyFx.day("2026-09-20", load: 90)
        XCTAssertEqual(engine.dayTrophies(for: rested, history: [twoDaysBefore, rested]), [])
    }

    func testGotThroughCarriesTheLabel() {
        let spikes = [
            LabelledSpike(title: "Stand-up", recoveryMinutes: 11),
            LabelledSpike(title: "Q3 planning", recoveryMinutes: 10)
        ]
        let day = TrophyFx.day("2026-09-22", labelled: spikes)
        XCTAssertEqual(engine.dayTrophies(for: day, history: []), [.gotThrough("Q3 planning")])
        XCTAssertEqual(DayTrophy.gotThrough("Q3 planning").title, "Got through 'Q3 planning'")
        XCTAssertEqual(DayTrophy.gotThrough(nil).title, "Got through it", "titles off")
        XCTAssertEqual(DayTrophy.gotThrough("  ").title, "Got through it")
        XCTAssertEqual(DayTrophy.gotThrough("Q3 planning").key, "got_through", "the label never travels with the key")
        XCTAssertEqual(DayTrophy.gotThrough("Q3 planning").shareTitle, "Got through it", "nor with the share title")
        XCTAssertEqual(DayTrophy.bouncedBack.shareTitle, DayTrophy.bouncedBack.title)

        let slow = TrophyFx.day("2026-09-22", labelled: [
            LabelledSpike(title: "Stand-up", recoveryMinutes: 11),
            LabelledSpike(title: "Moved", recoveryMinutes: nil)
        ])
        XCTAssertEqual(engine.dayTrophies(for: slow, history: []), [])
    }

    func testEarlyNightIsRelativeToYourOwnWeek() {
        // Usual bedtimes 23:30, 23:20, 23:40: median 30 minutes before midnight.
        let usual = [
            TrophyFx.day("2026-09-18", bedtime: "2026-09-17 23:30"),
            TrophyFx.day("2026-09-19", bedtime: "2026-09-18 23:20"),
            TrophyFx.day("2026-09-20", bedtime: "2026-09-19 23:40")
        ]
        let early = TrophyFx.day("2026-09-22", asleep: 430, bedtime: "2026-09-21 22:40")
        XCTAssertEqual(engine.dayTrophies(for: early, history: usual + [early]), [.earlyNight])

        let exactly = TrophyFx.day("2026-09-22", asleep: 420, bedtime: "2026-09-21 22:45")
        XCTAssertEqual(engine.dayTrophies(for: exactly, history: usual + [exactly]), [.earlyNight], "45 minutes on the dot")

        let notEarlyEnough = TrophyFx.day("2026-09-22", asleep: 430, bedtime: "2026-09-21 22:50")
        XCTAssertEqual(engine.dayTrophies(for: notEarlyEnough, history: usual + [notEarlyEnough]), [])

        let short = TrophyFx.day("2026-09-22", asleep: 400, bedtime: "2026-09-21 22:40")
        XCTAssertEqual(engine.dayTrophies(for: short, history: usual + [short]), [])

        XCTAssertEqual(engine.dayTrophies(for: early, history: Array(usual.prefix(2)) + [early]), [],
                       "needs three nights to compare with")

        let later = TrophyFx.day("2026-09-23", bedtime: "2026-09-22 20:00")
        XCTAssertEqual(engine.dayTrophies(for: early, history: usual + [early, later]), [.earlyNight],
                       "only nights before the day count")
    }

    func testQuietDayNeedsATrackedDay() {
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", still: 1), history: []), [.quietDay])
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", still: 0), history: []), [.quietDay])
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", still: 2), history: []), [])
        XCTAssertEqual(engine.dayTrophies(for: TrophyFx.day("2026-09-22", still: 0, tracked: false), history: []), [])
        XCTAssertTrue(TrophyEngine.zenDay(TrophyFx.day("2026-09-22", still: 0)))
        XCTAssertFalse(TrophyEngine.zenDay(TrophyFx.day("2026-09-22", still: 1)))
        XCTAssertFalse(TrophyEngine.zenDay(TrophyFx.day("2026-09-22", still: 0, tracked: false)))
    }

    func testTrophyWordingAndKeys() {
        XCTAssertEqual(DayTrophy.fastestRecovery.title, "Fastest bounce-back")
        XCTAssertEqual(DayTrophy.fastestRecovery.subtitle, "all time")
        XCTAssertEqual(DayTrophy.bestNight.subtitle, "all time")
        XCTAssertEqual(DayTrophy.bouncedBack.subtitle, "spiked, never stayed")
        XCTAssertEqual(DayTrophy.quietDay.title, "Quiet day")
        XCTAssertTrue(DayTrophy.calmestDay.isRecord)
        XCTAssertFalse(DayTrophy.earlyNight.isRecord)

        let all: [DayTrophy] = [.fastestRecovery, .calmestDay, .bestNight, .bouncedBack, .sleptItOff, .gotThrough(nil), .earlyNight, .quietDay]
        XCTAssertEqual(all.map { $0.key },
                       ["fastest_recovery", "calmest_day", "best_night", "bounced_back", "slept_it_off", "got_through", "early_night", "quiet_day"])
        for trophy in all {
            XCTAssertEqual(DayTrophy(key: trophy.key), trophy)
            XCTAssertFalse(trophy.rule.isEmpty)
        }
        XCTAssertEqual(DayTrophy(key: "got_through"), .gotThrough(nil))
        XCTAssertNil(DayTrophy(key: "heat3"))
    }

    // MARK: Week figures

    func testAttributionCountsThisWeek() {
        let days = [
            TrophyFx.day("2026-09-21", still: 3, moving: 1, workout: 1, night: 2),
            TrophyFx.day("2026-09-23", still: 2, moving: 2, workout: 0, night: 0),
            TrophyFx.day("2026-09-18", still: 9, moving: 9, workout: 9, night: 9),
            TrophyFx.day("2026-09-26", still: 9)
        ]
        let week = engine.week(containing: engine.now)
        XCTAssertEqual(week.start, TrophyFx.date("2026-09-21 00:00"))
        let counts = engine.attributionCounts(days, in: week)
        XCTAssertEqual(counts, AttributionCounts(still: 5, moving: 3, workout: 1, night: 2))
        XCTAssertEqual(counts.awake, 9, "in-bed rises stay out of the headline")
        XCTAssertEqual(engine.attributionCounts(days, in: engine.previousWeek(before: week)),
                       AttributionCounts(still: 9, moving: 9, workout: 9, night: 9))
        XCTAssertEqual(AttributionCounts(days: []), AttributionCounts(still: 0, moving: 0, workout: 0, night: 0))
    }

    func testAverageBounceBackThisWeek() {
        let days = [
            TrophyFx.day("2026-09-21", recovery: 9),
            TrophyFx.day("2026-09-22", recovery: nil),
            TrophyFx.day("2026-09-23", recovery: 12),
            TrophyFx.day("2026-09-18", recovery: 30),
            TrophyFx.day("2026-09-26", recovery: 1)
        ]
        XCTAssertEqual(engine.averageBounceBack(days) ?? 0, 10.5 * 60, accuracy: 0.001)
        XCTAssertNil(engine.averageBounceBack([TrophyFx.day("2026-09-22")]))
        XCTAssertNil(engine.averageBounceBack([]))
    }

    func testWeekBarsPerDay() {
        let spikes = [
            TrophyFx.date("2026-09-21 09:00"),
            TrophyFx.date("2026-09-24 10:00"),
            TrophyFx.date("2026-09-19 20:00"),
            TrophyFx.date("2026-09-26 20:00")
        ]
        let bars = engine.weekBars(spikes)
        XCTAssertEqual(bars.thisWeek.map { $0.count }, [1, 0, 0, 1, 0, 0, 0])
        XCTAssertEqual(bars.lastWeek.map { $0.count }, [0, 0, 0, 0, 0, 1, 0])
        XCTAssertEqual(bars.thisWeek.first?.day.start, TrophyFx.date("2026-09-21 00:00"))
        XCTAssertEqual(bars.thisWeekTotal, 2)
        XCTAssertEqual(bars.lastWeekTotal, 1)
    }

    func testDailyCountsAcrossFallBack() {
        let dst = TrophyFx.engine("2026-10-28 12:00")
        let week = dst.week(containing: dst.now)
        let days = dst.dailyCounts([TrophyFx.date("2026-10-27 08:00")], in: week)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map { $0.count }, [0, 1, 0, 0, 0, 0, 0])
        XCTAssertEqual(days.last?.day.duration, 25 * 3600)
    }

    // MARK: Streak

    func testRecapStreakPausesOnUnwornDays() {
        let opened = TrophyFx.days(18...23)
        XCTAssertEqual(engine.recapStreak(opened), RecapStreak(current: 6, best: 6), "today has no ledger yet")

        let today = TrophyFx.day("2026-09-24", opened: false)
        XCTAssertEqual(engine.recapStreak(opened + [today]), RecapStreak(current: 6, best: 6), "today is still filling up")
        XCTAssertEqual(engine.recapStreak(opened + [TrophyFx.day("2026-09-24")]), RecapStreak(current: 7, best: 7))
        XCTAssertEqual(engine.recapStreak(opened + [TrophyFx.day("2026-09-26")]), RecapStreak(current: 6, best: 6), "future days never count")

        var paused = opened
        paused[2] = TrophyFx.day("2026-09-20", opened: false, worn: false)
        XCTAssertEqual(engine.recapStreak(paused), RecapStreak(current: 5, best: 5))

        var broken = opened
        broken[2] = TrophyFx.day("2026-09-20", opened: false)
        XCTAssertEqual(engine.recapStreak(broken), RecapStreak(current: 3, best: 3))

        let gap = opened.filter { !engine.calendar.isDate($0.day, inSameDayAs: TrophyFx.date("2026-09-20 00:00")) }
        XCTAssertEqual(engine.recapStreak(gap), RecapStreak(current: 3, best: 3), "a missing day breaks the run")

        let old = TrophyFx.days(1...8, month: "08")
        XCTAssertEqual(engine.recapStreak(old + opened), RecapStreak(current: 6, best: 8))
        XCTAssertEqual(engine.recapStreak([]), RecapStreak(current: 0, best: 0))
    }

    // MARK: Badges

    func testBadges() {
        let bouncy = TrophyFx.day("2026-09-10", still: 3, recovery: 6)
        let zen = TrophyFx.day("2026-09-11", still: 0)
        XCTAssertEqual(engine.earnedBadges([bouncy, zen]), [.bouncedBack, .zenDay])

        let heavy = TrophyFx.day("2026-09-12", load: 70)
        let rested = TrophyFx.day("2026-09-13", sleep: 85)
        XCTAssertEqual(engine.earnedBadges([heavy, rested]), [.sleptItOff])
        XCTAssertEqual(engine.earnedBadges([rested]), [])

        let meeting = TrophyFx.day("2026-09-14", labelled: [LabelledSpike(title: "1:1", recoveryMinutes: 4)])
        XCTAssertEqual(engine.earnedBadges([meeting]), [.gotThrough])

        let week = TrophyFx.days(15...21)
        XCTAssertEqual(engine.earnedBadges(week), [.steady])
        XCTAssertEqual(engine.earnedBadges(Array(week.dropLast())), [])
        XCTAssertEqual(engine.earnedBadges([]), [])
    }

    func testBadgeDetailLevelsAndNext() {
        let hits = (1...5).map { TrophyFx.day(String(format: "2026-09-%02ld", $0), still: 3, recovery: 5) }
        let detail = engine.badgeDetail(.bouncedBack, days: hits)
        XCTAssertTrue(detail.isEarned)
        XCTAssertEqual(detail.earnedAt, TrophyFx.date("2026-09-01 00:00"), "the first day that earned it")
        XCTAssertEqual(detail.level, 5)
        XCTAssertEqual(detail.next, TierProgress(current: 5, target: 25, unit: .days))
        XCTAssertEqual(detail.next?.fraction ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(detail.subtitle, "5 days so far")
        XCTAssertEqual(detail.id, "badge-bouncedBack")
        XCTAssertEqual(detail.title, "Bounced back")

        let locked = engine.badgeDetail(.zenDay, days: hits)
        XCTAssertFalse(locked.isEarned)
        XCTAssertNil(locked.level, "locked badges have no level")
        XCTAssertEqual(locked.subtitle, "Not earned yet")
        XCTAssertEqual(locked.next, TierProgress(current: 0, target: 1, unit: .days))
        XCTAssertEqual(locked.next?.remaining, 1)

        let many = (1...26).map { TrophyFx.day(String(format: "2026-08-%02ld", $0), still: 3, recovery: 5) }
        let top = engine.badgeDetail(.bouncedBack, days: many)
        XCTAssertNil(top.next, "top level reached")
        XCTAssertEqual(top.level, 25, "the medal reads 25")
    }

    func testSteadyShowsWhenEarnedAndTheNextLevel() {
        let eight = TrophyFx.days(14...21)
        let detail = engine.badgeDetail(.steady, days: eight)
        XCTAssertTrue(detail.isEarned)
        XCTAssertEqual(detail.earnedAt, TrophyFx.date("2026-09-20 00:00"), "the 7th day in a row")
        XCTAssertEqual(detail.next, TierProgress(current: 8, target: 14, unit: .days))
        XCTAssertEqual(detail.next?.currentLabel, "8 days")
        XCTAssertEqual(detail.next?.targetLabel, "14 days")
        XCTAssertEqual(detail.next?.fraction ?? 0, 8.0 / 14.0, accuracy: 0.0001)
        XCTAssertEqual(detail.subtitle, "Best run: 8 days")
        XCTAssertEqual(detail.level, 7)
        XCTAssertEqual(detail.id, "badge-steady")

        let six = TrophyFx.days(16...21)
        let lockedDetail = engine.badgeDetail(.steady, days: six)
        XCTAssertFalse(lockedDetail.isEarned)
        XCTAssertEqual(lockedDetail.next, TierProgress(current: 6, target: 7, unit: .days))
        XCTAssertEqual(lockedDetail.next?.currentLabel, "6 days")
    }

    func testDetailsAgreeWithEarnedBadges() {
        let sets: [[DayLedger]] = [
            [],
            [TrophyFx.day("2026-09-10", still: 3, recovery: 6), TrophyFx.day("2026-09-11", still: 0)],
            [TrophyFx.day("2026-09-12", load: 70), TrophyFx.day("2026-09-13", sleep: 85)],
            TrophyFx.days(14...21)
        ]
        for days in sets {
            let details = engine.badgeDetails(days)
            XCTAssertEqual(details.count, Badge.allCases.count)
            let earned = Set(zip(Badge.allCases, details).filter { $0.1.isEarned }.map { $0.0 })
            XCTAssertEqual(earned, engine.earnedBadges(days))
        }
    }

    func testBouncedBackDetailPointsAtTheFastestDay() {
        let history = [
            TrophyFx.day("2026-09-10", still: 3, recovery: 5),
            TrophyFx.day("2026-09-12", still: 3, recovery: 9)
        ]
        let day = TrophyFx.day("2026-09-20", still: 3, recovery: 7)
        let detail = engine.trophyDetail(.bouncedBack, for: day, history: history + [day])
        XCTAssertEqual(detail.next, TierProgress(current: 7, target: 5, unit: .minutes, lowerIsBetter: true))
        XCTAssertEqual(detail.next?.fraction ?? 0, 5.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(detail.next?.remaining, 2)
        XCTAssertEqual(detail.next?.targetLabel, "5 min")
        XCTAssertEqual(detail.earnedAt, day.day)
        XCTAssertEqual(detail.id, "trophy-20260920-bounced_back")
        XCTAssertEqual(detail.title, "Bounced back")
        XCTAssertTrue(detail.isEarned)
        XCTAssertNil(engine.trophyDetail(.bouncedBack, for: history[0], history: history).next, "already the fastest")

        let record = engine.trophyDetail(.fastestRecovery, for: day, history: history + [day])
        XCTAssertNil(record.next, "records have no next level")
        XCTAssertEqual(record.subtitle, "all time")
        XCTAssertNil(record.level)
        XCTAssertFalse(record.rule.isEmpty)
    }

    func testTierUnitFormat() {
        XCTAssertEqual(TierUnit.days.format(1), "1 day")
        XCTAssertEqual(TierUnit.days.format(14), "14 days")
        XCTAssertEqual(TierUnit.minutes.format(8), "8 min")
        XCTAssertEqual(TierProgress(current: 3, target: 0, unit: .days).fraction, 1)
        XCTAssertEqual(TierProgress(current: 0, target: 5, unit: .minutes, lowerIsBetter: true).fraction, 1)
    }

    // RECAP 0.1 and 0.4: describe the body, never the person; no exclamation marks.
    func testTrophyStringsNeverNameACondition() {
        let banned = ["panic", "anxiety", "anxious", "depress", "burnout", "burned out", "disorder",
                      "symptom", "diagnos", "episode", "stressed out", "unhealthy", "!"]
        var strings: [String] = []
        for badge in Badge.allCases {
            strings += [badge.title, badge.hint, badge.rule]
        }
        let trophies: [DayTrophy] = [.fastestRecovery, .calmestDay, .bestNight, .bouncedBack, .sleptItOff,
                                     .gotThrough("Q3 planning"), .gotThrough(nil), .earlyNight, .quietDay]
        for trophy in trophies {
            strings += [trophy.title, trophy.shareTitle, trophy.subtitle, trophy.rule]
        }
        strings.append(engine.badgeDetail(.zenDay, days: []).subtitle)
        for string in strings {
            XCTAssertFalse(string.isEmpty)
            for word in banned {
                XCTAssertFalse(string.lowercased().contains(word), "\"\(string)\" contains \"\(word)\"")
            }
        }
    }
}
