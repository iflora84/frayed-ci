import Foundation

/// Sample history for `-demo` (screenshots, App Review): fourteen days of
/// synthetic RecapInputs run through the real engine, so every headline,
/// type and one-liner is the engine's own text. Everything is fixed apart
/// from the dates moving with today.
enum DemoData {
    static let userId = "demo"
    static let restingHistory = [57, 58, 59, 58, 58, 57, 58]
    static let hrvBaseline = 46.0
    static let sleepWeekMeanHours = 6.9

    private struct Spike {
        let peakAt: String
        let peak: Int
        let minutes: Int
        let recovery: Int?
    }

    private struct Workout {
        let start: String
        let end: String
        let peak: Int
        let kind: String
    }

    private struct Rise {
        let peakAt: String
        let peak: Int
        let awake: Bool
    }

    private struct Night {
        let start: String
        let end: String
        let asleep: Int
        let awake: Int
        let awakenings: Int
        let lowHR: Int
    }

    private struct Spec {
        let daysAgo: Int
        let coverage: Double
        let awakeHours: Double
        let night: Night?
        let hrvNight: Double?
        let stills: [Spike]
        let moving: [Spike]
        let workouts: [Workout]
        let rises: [Rise]
        let calmestAt: String
        let calmestBpm: Int
    }

    // Today: 7 daytime spikes (2 workout, 1 moving, 4 still), every still one
    // recovered, plus one awake rise in bed. Then a mix: a rough night (2), a
    // heavy day (3), the Watch left on the charger (4), a fast day (5), a day
    // with nothing still (6), a short night (12).
    private static let specs: [Spec] = [
        Spec(daysAgo: 0, coverage: 0.93, awakeHours: 13.5,
             night: Night(start: "23:30", end: "06:20", asleep: 380, awake: 30, awakenings: 3, lowHR: 49), hrvNight: 48,
             stills: [Spike(peakAt: "08:15", peak: 101, minutes: 12, recovery: 8),
                      Spike(peakAt: "10:40", peak: 108, minutes: 15, recovery: 9),
                      Spike(peakAt: "14:10", peak: 117, minutes: 25, recovery: 12),
                      Spike(peakAt: "16:30", peak: 96, minutes: 10, recovery: 7)],
             moving: [Spike(peakAt: "12:05", peak: 97, minutes: 10, recovery: nil)],
             workouts: [Workout(start: "07:00", end: "07:40", peak: 158, kind: "running"),
                        Workout(start: "18:00", end: "18:30", peak: 132, kind: "strength")],
             rises: [Rise(peakAt: "02:45", peak: 94, awake: true)],
             calmestAt: "12:40", calmestBpm: 61),
        Spec(daysAgo: 1, coverage: 0.9, awakeHours: 13,
             night: Night(start: "23:50", end: "06:40", asleep: 395, awake: 15, awakenings: 2, lowHR: 52), hrvNight: 45,
             stills: [Spike(peakAt: "09:20", peak: 98, minutes: 10, recovery: 9),
                      Spike(peakAt: "11:50", peak: 104, minutes: 18, recovery: 14),
                      Spike(peakAt: "15:30", peak: 95, minutes: 8, recovery: 6)],
             moving: [Spike(peakAt: "12:40", peak: 99, minutes: 12, recovery: nil)],
             workouts: [], rises: [],
             calmestAt: "16:50", calmestBpm: 60),
        Spec(daysAgo: 2, coverage: 0.91, awakeHours: 13,
             night: Night(start: "23:40", end: "06:10", asleep: 290, awake: 70, awakenings: 5, lowHR: 55), hrvNight: 36,
             stills: [Spike(peakAt: "10:10", peak: 101, minutes: 14, recovery: 11),
                      Spike(peakAt: "14:45", peak: 107, minutes: 20, recovery: 18)],
             moving: [], workouts: [],
             rises: [Rise(peakAt: "01:20", peak: 96, awake: true),
                     Rise(peakAt: "03:05", peak: 99, awake: true),
                     Rise(peakAt: "04:40", peak: 93, awake: true)],
             calmestAt: "13:20", calmestBpm: 63),
        Spec(daysAgo: 3, coverage: 0.94, awakeHours: 14,
             night: Night(start: "00:30", end: "06:20", asleep: 350, awake: 20, awakenings: 3, lowHR: 56), hrvNight: 34,
             stills: [Spike(peakAt: "08:50", peak: 103, minutes: 12, recovery: 10),
                      Spike(peakAt: "10:30", peak: 111, minutes: 28, recovery: 22),
                      Spike(peakAt: "12:15", peak: 99, minutes: 10, recovery: 9),
                      Spike(peakAt: "14:40", peak: 118, minutes: 35, recovery: 25),
                      Spike(peakAt: "17:05", peak: 105, minutes: 18, recovery: 16)],
             moving: [], workouts: [], rises: [],
             calmestAt: "19:30", calmestBpm: 64),
        Spec(daysAgo: 4, coverage: 0, awakeHours: 0, night: nil, hrvNight: nil,
             stills: [], moving: [], workouts: [], rises: [], calmestAt: "12:00", calmestBpm: 0),
        Spec(daysAgo: 5, coverage: 0.9, awakeHours: 13.5,
             night: Night(start: "23:20", end: "06:50", asleep: 430, awake: 12, awakenings: 1, lowHR: 50), hrvNight: 50,
             stills: [Spike(peakAt: "09:05", peak: 94, minutes: 8, recovery: 5),
                      Spike(peakAt: "13:10", peak: 97, minutes: 9, recovery: 7)],
             moving: [],
             workouts: [Workout(start: "18:00", end: "18:35", peak: 150, kind: "running")],
             rises: [],
             calmestAt: "15:40", calmestBpm: 59),
        Spec(daysAgo: 6, coverage: 0.9, awakeHours: 13,
             night: Night(start: "23:45", end: "06:30", asleep: 390, awake: 15, awakenings: 2, lowHR: 51), hrvNight: 44,
             stills: [],
             moving: [Spike(peakAt: "12:30", peak: 99, minutes: 14, recovery: nil)],
             workouts: [Workout(start: "07:10", end: "07:50", peak: 156, kind: "cycling")],
             rises: [],
             calmestAt: "14:10", calmestBpm: 58),
        Spec(daysAgo: 7, coverage: 0.88, awakeHours: 12.5,
             night: Night(start: "23:30", end: "06:35", asleep: 405, awake: 15, awakenings: 2, lowHR: 52), hrvNight: 47,
             stills: [Spike(peakAt: "11:20", peak: 96, minutes: 9, recovery: 8)],
             moving: [], workouts: [], rises: [],
             calmestAt: "16:00", calmestBpm: 60),
        Spec(daysAgo: 8, coverage: 0.92, awakeHours: 13,
             night: Night(start: "23:55", end: "06:40", asleep: 380, awake: 20, awakenings: 2, lowHR: 53), hrvNight: 43,
             stills: [Spike(peakAt: "08:30", peak: 100, minutes: 14, recovery: 12),
                      Spike(peakAt: "13:00", peak: 109, minutes: 22, recovery: 19),
                      Spike(peakAt: "16:40", peak: 97, minutes: 12, recovery: 11)],
             moving: [Spike(peakAt: "12:20", peak: 98, minutes: 10, recovery: nil)],
             workouts: [], rises: [],
             calmestAt: "12:10", calmestBpm: 61),
        Spec(daysAgo: 9, coverage: 0.9, awakeHours: 13,
             night: Night(start: "00:10", end: "06:30", asleep: 360, awake: 15, awakenings: 2, lowHR: 54), hrvNight: 41,
             stills: [Spike(peakAt: "10:00", peak: 102, minutes: 30, recovery: 26),
                      Spike(peakAt: "15:20", peak: 106, minutes: 34, recovery: 31)],
             moving: [], workouts: [], rises: [],
             calmestAt: "18:20", calmestBpm: 62),
        Spec(daysAgo: 10, coverage: 0.93, awakeHours: 13.5,
             night: Night(start: "23:30", end: "06:20", asleep: 400, awake: 10, awakenings: 1, lowHR: 51), hrvNight: 48,
             stills: [Spike(peakAt: "09:10", peak: 99, minutes: 11, recovery: 9),
                      Spike(peakAt: "11:30", peak: 103, minutes: 15, recovery: 13),
                      Spike(peakAt: "14:00", peak: 97, minutes: 9, recovery: 8),
                      Spike(peakAt: "16:50", peak: 101, minutes: 12, recovery: 10)],
             moving: [],
             workouts: [Workout(start: "07:00", end: "07:30", peak: 152, kind: "running")],
             rises: [],
             calmestAt: "13:30", calmestBpm: 60),
        Spec(daysAgo: 11, coverage: 0.89, awakeHours: 12.5,
             night: Night(start: "23:40", end: "06:50", asleep: 415, awake: 12, awakenings: 1, lowHR: 50), hrvNight: 46,
             stills: [Spike(peakAt: "14:20", peak: 95, minutes: 8, recovery: 7)],
             moving: [], workouts: [],
             rises: [Rise(peakAt: "04:10", peak: 92, awake: false)],
             calmestAt: "15:10", calmestBpm: 59),
        Spec(daysAgo: 12, coverage: 0.9, awakeHours: 13,
             night: Night(start: "01:30", end: "06:10", asleep: 260, awake: 20, awakenings: 2, lowHR: 57), hrvNight: 38,
             stills: [Spike(peakAt: "10:40", peak: 100, minutes: 14, recovery: 12),
                      Spike(peakAt: "15:00", peak: 98, minutes: 10, recovery: 9)],
             moving: [], workouts: [], rises: [],
             calmestAt: "12:50", calmestBpm: 63),
        Spec(daysAgo: 13, coverage: 0.91, awakeHours: 13,
             night: Night(start: "23:20", end: "06:40", asleep: 420, awake: 15, awakenings: 2, lowHR: 51), hrvNight: 45,
             stills: [Spike(peakAt: "09:40", peak: 97, minutes: 11, recovery: 10),
                      Spike(peakAt: "12:30", peak: 101, minutes: 16, recovery: 15),
                      Spike(peakAt: "17:10", peak: 95, minutes: 8, recovery: 7)],
             moving: [], workouts: [], rises: [],
             calmestAt: "14:40", calmestBpm: 60)
    ]

    // MARK: Recaps

    /// 14 days, newest first; today reads "7 spikes, every one came down".
    static func recaps(calendar: Calendar, now: Date) -> [DayRecap] {
        return days(calendar: calendar, now: now).map { $0.recap }
    }

    /// One `.recap` moment per day, newest first.
    static func moments(calendar: Calendar, now: Date) -> [Moment] {
        let built = days(calendar: calendar, now: now).enumerated().compactMap { index, day in
            moment(for: day.recap, dayStart: day.dayStart, index: index)
        }
        return Moment.newestFirst(built)
    }

    private static func days(calendar: Calendar, now: Date) -> [(dayStart: Date, recap: DayRecap)] {
        return specs.compactMap { spec -> (dayStart: Date, recap: DayRecap)? in
            guard let day = calendar.date(byAdding: .day, value: -spec.daysAgo, to: now) else {
                return nil
            }
            let clock = Clock(day: day, calendar: calendar)
            let recapInput = input(spec, clock: clock, now: now)
            var recap = RecapEngine.generate(recapInput, calendar: calendar)
            if recap.coverage > 0 {
                recap.beats = beats(for: recap, input: recapInput)
            }
            return (clock.at("04:00"), recap)
        }
    }

    /// A made-up minute-by-minute curve that passes through every spike's
    /// peak and settles where the spec says, so the day chart and the spike
    /// detail have something to draw. Set after generation so the recap's
    /// numbers stay exactly the spec's.
    private static func beats(for recap: DayRecap, input: RecapInput) -> [DayRecap.Beat] {
        let resting = recap.restingHR
        let start = input.night.map { min($0.start, input.dayStart) } ?? input.dayStart
        var beats: [DayRecap.Beat] = []
        var at = start
        var i = 0
        while at <= input.now {
            let asleep = input.night.map { at >= $0.start && at <= $0.end } ?? false
            let floor = asleep ? (input.night?.lowHR ?? resting - 6) + 2 : resting + 4
            var bpm = floor + (i * 37 % 7) - 3
            for spike in recap.spikes {
                let settled = spike.recoveredAt ?? spike.end.addingTimeInterval(5 * 60)
                if at >= spike.start && at <= spike.peakAt {
                    let span = max(spike.peakAt.timeIntervalSince(spike.start), 60)
                    bpm = max(bpm, floor + Int(Double(spike.peak - floor) * at.timeIntervalSince(spike.start) / span))
                } else if at > spike.peakAt && at <= settled {
                    let span = max(settled.timeIntervalSince(spike.peakAt), 60)
                    let left = 1 - at.timeIntervalSince(spike.peakAt) / span
                    bpm = max(bpm, floor + Int(Double(spike.peak - floor) * left * left))
                }
            }
            beats.append(DayRecap.Beat(at: at, bpm: bpm))
            at = at.addingTimeInterval(120)
            i += 1
        }
        return beats
    }

    /// "HH:mm" on the spec's day; a night start at or after noon belongs to
    /// the evening before, like the golden fixtures.
    private struct Clock {
        let day: Date
        let calendar: Calendar

        func at(_ hhmm: String, _ dayOffset: Int = 0) -> Date {
            let parts = hhmm.split(separator: ":").compactMap { Int($0) }
            let hour = parts.count > 0 ? parts[0] : 0
            let minute = parts.count > 1 ? parts[1] : 0
            let midnight = calendar.startOfDay(for: day)
            let base = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: midnight) ?? midnight
            return calendar.date(byAdding: .day, value: dayOffset, to: base) ?? base
        }

        func nightStart(_ hhmm: String) -> Date {
            let hour = Int(hhmm.prefix(2)) ?? 0
            return at(hhmm, hour >= 12 ? -1 : 0)
        }
    }

    private static func input(_ spec: Spec, clock: Clock, now: Date) -> RecapInput {
        let dayStart = clock.at("04:00")
        // Every day reads as finished, today included, whatever time the demo runs.
        let generatedAt = spec.daysAgo == 0 ? max(now, clock.at("20:05")) : clock.at("20:05")
        var input = RecapInput(
            dayKey: WeekReceipt.dayKey(dayStart, calendar: clock.calendar),
            dayStart: dayStart,
            now: generatedAt,
            recapTime: clock.at("20:00"),
            userId: userId,
            restingHistory: restingHistory,
            coverage: spec.coverage,
            awakeTrackedHours: spec.awakeHours,
            crisisNumber: "988"
        )
        input.recapDays = specs.count - spec.daysAgo
        input.baselineNights = 7
        input.hrvBaseline = hrvBaseline
        input.sleepWeekMeanHours = sleepWeekMeanHours
        if spec.daysAgo == 4 {
            input.coverageYesterday = 0.9
            return input
        }
        input.recoveryMedian7d = spec.daysAgo >= 12 ? nil : 11
        input.recoveryBest7d = spec.daysAgo >= 12 ? nil : RecapInput.RecoveryBest(weekday: "Sunday", minutes: 6)

        var night: RecapInput.Night? = nil
        if let n = spec.night {
            let start = clock.nightStart(n.start)
            night = RecapInput.Night(start: start, end: clock.at(n.end), asleepMinutes: n.asleep,
                                     awakeMinutes: n.awake, awakenings: n.awakenings, lowHR: n.lowHR)
            if let sdnn = spec.hrvNight {
                input.hrv = [RecapInput.HRVReading(date: start.addingTimeInterval(3 * 3600), sdnn: sdnn)]
            }
        }
        input.night = night

        var runs: [RecapInput.Run] = []
        for (i, s) in spec.stills.enumerated() {
            runs.append(run("s\(i)", s, clock: clock, stepsPadded: 4))
        }
        for (i, s) in spec.moving.enumerated() {
            runs.append(run("m\(i)", s, clock: clock, stepsPadded: 320))
        }
        for (i, w) in spec.workouts.enumerated() {
            let start = clock.at(w.start)
            let end = clock.at(w.end)
            input.workouts.append(RecapInput.Workout(start: start, end: end, kind: w.kind))
            input.exercise.append(RecapInput.Interval(start: start, end: end))
            let peakAt = start.addingTimeInterval(end.timeIntervalSince(start) * 2 / 3)
            runs.append(RecapInput.Run(id: "w\(i)", start: start, end: end, peakAt: peakAt, peak: w.peak))
        }
        for (i, r) in spec.rises.enumerated() {
            let peakAt = clock.at(r.peakAt)
            runs.append(RecapInput.Run(
                id: "n\(i)", start: peakAt.addingTimeInterval(-4 * 60), end: peakAt.addingTimeInterval(6 * 60),
                peakAt: peakAt, peak: r.peak, stage: r.awake ? .awake : .rem
            ))
        }
        input.runs = runs
        if !spec.workouts.isEmpty {
            input.activeEnergyKcal = Double(spec.workouts.reduce(0) { $0 + $1.peak * 3 })
        }
        input.calmest = DayRecap.Calmest(at: clock.at(spec.calmestAt), bpm: spec.calmestBpm)
        return input
    }

    private static func run(_ id: String, _ s: Spike, clock: Clock, stepsPadded: Double) -> RecapInput.Run {
        let peakAt = clock.at(s.peakAt)
        return RecapInput.Run(
            id: id,
            start: peakAt.addingTimeInterval(-3 * 60),
            end: peakAt.addingTimeInterval(TimeInterval(max(2, s.minutes - 3) * 60)),
            peakAt: peakAt,
            peak: s.peak,
            stepsPadded: stepsPadded,
            motionActive: stepsPadded >= 100,
            recoveredAt: s.recovery.map { peakAt.addingTimeInterval(TimeInterval($0 * 60)) }
        )
    }

    // MARK: Moments

    private static func moment(for recap: DayRecap, dayStart: Date, index: Int) -> Moment? {
        let summary = Moment.RecapSummary(
            spikeCount: recap.counts.daytime,
            stillCount: recap.counts.still,
            movingCount: recap.counts.moving,
            workoutCount: recap.counts.workout,
            noticedCount: recap.counts.noticed,
            load: recap.load?.total,
            recoverySeconds: recap.recovery?.median.map { Int(($0 * 60).rounded()) },
            calmestBpm: recap.calmest?.bpm,
            dayType: recap.type?.rawValue,
            coverage: recap.coverage,
            hourlyPeaks: hourlyPeaks(recap, dayStart: dayStart)
        )
        var night: Moment.NightSummary? = nil
        if let n = recap.lastNight {
            night = Moment.NightSummary(
                asleepMinutes: n.asleepMinutes, awakeMinutes: n.awakeMinutes, awakenings: n.awakenings,
                lowestHR: n.lowHR, sleepScore: nil, awakeRises: recap.counts.inBedAwake,
                asleepRises: recap.counts.inBedAsleep, hrvNight: n.hrvNight, hrvBaseline: n.hrvBaseline
            )
        }
        return try? Moment(
            id: fixedID(index),
            start: dayStart,
            end: dayStart.addingTimeInterval(Moment.maxDuration),
            kind: .recap,
            peakHR: recap.spikes.map { $0.peak }.max(),
            restingHR: recap.restingHR,
            source: .health,
            visibility: demoVisibility[index] ?? .private,
            recap: summary,
            night: night
        )
    }

    /// Today stays private so the demo shows "Post today to the feed"; two
    /// earlier days are posted so the feed has the user's own cards.
    private static let demoVisibility: [Int: MomentVisibility] = [1: .friends, 2: .anonymous]

    /// The share strip: each hour's highest spike, a quiet reading a little
    /// over resting where nothing happened, 0 where the Watch had no data.
    private static func hourlyPeaks(_ recap: DayRecap, dayStart: Date) -> [Int] {
        guard !recap.isNotWorn else {
            return []
        }
        return (0..<Moment.RecapSummary.stripLength).map { hour -> Int in
            let start = dayStart.addingTimeInterval(TimeInterval(hour * 3600))
            let end = start.addingTimeInterval(3600)
            if start > recap.generatedAt {
                return 0
            }
            let peaks = recap.spikes.filter { $0.peakAt >= start && $0.peakAt < end }.map { $0.peak }
            if let top = peaks.max() {
                return top
            }
            return recap.restingHR + 6 + (hour * 5) % 7
        }
    }

    static func fixedID(_ index: Int) -> UUID {
        let text = String(format: "00000000-0000-4000-8000-%012d", index)
        return UUID(uuidString: text) ?? UUID()
    }

    // MARK: Friends

    /// Three posts for the feed until real friends arrive (canvas R-Feed).
    static let friendPosts: [FeedSample] = [
        FeedSample(
            id: "demo-maya",
            author: "Maya R.",
            initials: "MR",
            anonymous: false,
            hoursAgo: 2,
            dayType: "Night shift",
            headline: "About 55 min awake in bed.",
            subline: "3 wake-ups the Watch caught.",
            body: .payStub([
                FeedSampleLine(label: "Employee", value: "your heart"),
                FeedSampleLine(label: "Hours awake in bed", value: "about 55 min"),
                FeedSampleLine(label: "Clock-ins the Watch caught", value: "3"),
                FeedSampleLine(label: "Net pay", value: "0.00"),
                FeedSampleLine(label: "Employer", value: "unknown")
            ]),
            reactionCounts: [.hug: 4, .same: 2]
        ),
        FeedSample(
            id: "demo-heron",
            author: "Cautious Heron",
            initials: "CH",
            anonymous: true,
            hoursAgo: 5,
            dayType: "Meeting survivor",
            headline: "Long afternoon",
            subline: "A permission slip, signed.",
            body: .permissionSlip(
                text: "Please excuse Cautious Heron from the next meeting. Their heart has already attended three today and left two of them early.",
                signed: "Signed, a Watch."
            ),
            reactionCounts: [.same: 6, .proud: 1]
        ),
        FeedSample(
            id: "demo-priya",
            author: "Priya",
            initials: "P",
            anonymous: false,
            hoursAgo: 9,
            dayType: "Slow burner",
            headline: "Slow burner · 3 spikes",
            subline: "Nothing dramatic. Just on, for a while.",
            body: .recap(summary: Moment.RecapSummary(
                spikeCount: 3, stillCount: 3, movingCount: 0, workoutCount: 0, noticedCount: 1,
                load: 38, recoverySeconds: 22 * 60, calmestBpm: 62, dayType: DayType.slowBurner.rawValue, coverage: 0.9,
                hourlyPeaks: [0, 0, 0, 66, 68, 71, 84, 70, 69, 96, 88, 72, 70, 74, 101, 91, 73, 70, 69, 68, 67, 66, 0, 0]
            )),
            reactionCounts: [.checking: 2, .hug: 1]
        )
    ]
}
