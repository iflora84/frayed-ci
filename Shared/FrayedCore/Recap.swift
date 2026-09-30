import Foundation

// The daily recap engine (docs/RECAP.md sections 1-6 and 9). Pure Foundation:
// the clock and the calendar come in through RecapInput and generate(_:),
// so the same input always produces the same DayRecap.

/// What the engine gets after the HealthKit layer has normalised the day:
/// runs already merged by the detector, sleep grouped into a night, and the
/// 7-day aggregates read from the recap cache. Raw samples ride along for
/// the parts the engine derives itself (calmest moment, in-bed stage,
/// recovery from samples, padded step counts).
struct RecapInput: Hashable {
    enum Motion: String, Codable, Hashable {
        case notSet, sedentary, active
    }

    struct HeartRateSample: Codable, Hashable {
        var date: Date
        var bpm: Int
        var motion: Motion

        init(date: Date, bpm: Int, motion: Motion = .notSet) {
            self.date = date
            self.bpm = bpm
            self.motion = motion
        }
    }

    /// One per-minute step bucket, merged across sources.
    struct Steps: Codable, Hashable {
        var start: Date
        var end: Date
        var count: Double
    }

    struct Workout: Codable, Hashable {
        var start: Date
        var end: Date
        var kind: String?

        init(start: Date, end: Date, kind: String? = nil) {
            self.start = start
            self.end = end
            self.kind = kind
        }
    }

    /// An Apple exercise minute, or any other plain interval.
    struct Interval: Codable, Hashable {
        var start: Date
        var end: Date
    }

    enum SleepStage: String, Codable, Hashable {
        case inBed, awake, core, deep, rem, unspecified

        var isAsleep: Bool {
            switch self {
            case .core, .deep, .rem, .unspecified: return true
            case .inBed, .awake: return false
            }
        }
    }

    struct SleepSample: Codable, Hashable {
        var start: Date
        var end: Date
        var stage: SleepStage
    }

    struct HRVReading: Codable, Hashable {
        var date: Date
        var sdnn: Double
    }

    struct Caffeine: Codable, Hashable {
        var date: Date
        var mg: Double
    }

    struct Event: Codable, Hashable {
        var id: String
        var title: String?
        var start: Date
        var end: Date
        /// Attendees excluding the user; 0 is a solo block.
        var people: Int
        var isAllDay: Bool
        var isCanceled: Bool
        var isDeclined: Bool

        init(id: String, title: String? = nil, start: Date, end: Date, people: Int,
             isAllDay: Bool = false, isCanceled: Bool = false, isDeclined: Bool = false) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
            self.people = people
            self.isAllDay = isAllDay
            self.isCanceled = isCanceled
            self.isDeclined = isDeclined
        }
    }

    struct CalendarAccess: Codable, Hashable {
        var access: Bool
        var showTitles: Bool
        var events: [Event]
        var hintDismissed: Bool

        init(access: Bool = false, showTitles: Bool = false, events: [Event] = [], hintDismissed: Bool = false) {
            self.access = access
            self.showTitles = showTitles
            self.events = events
            self.hintDismissed = hintDismissed
        }
    }

    /// Last night, already grouped (RECAP 1: longest session ending 00:00-14:00).
    struct Night: Codable, Hashable {
        var start: Date
        var end: Date
        var asleepMinutes: Int
        var awakeMinutes: Int
        var awakenings: Int
        var lowHR: Int?
    }

    /// A merged run of elevated readings from the detector.
    struct Run: Codable, Hashable {
        var id: String
        var start: Date
        var end: Date
        var peakAt: Date
        var peak: Int
        /// Every reading in [start, end], low ones included. May be empty
        /// when the layer passes summary fields instead.
        var samples: [HeartRateSample]
        /// Steps in [start - 5 min, end + 5 min]; nil means derive from `steps`.
        var stepsPadded: Double?
        /// Any reading in the run carried the active motion context.
        var motionActive: Bool
        /// First reading at or under resting + 10 after the peak; nil means
        /// derive from `samples`.
        var recoveredAt: Date?
        /// Sleep stage at the peak for an in-bed run; nil means derive from `sleep`.
        var stage: SleepStage?
        var tag: SpikeTag?

        init(id: String, start: Date, end: Date, peakAt: Date, peak: Int,
             samples: [HeartRateSample] = [], stepsPadded: Double? = nil, motionActive: Bool = false,
             recoveredAt: Date? = nil, stage: SleepStage? = nil, tag: SpikeTag? = nil) {
            self.id = id
            self.start = start
            self.end = end
            self.peakAt = peakAt
            self.peak = peak
            self.samples = samples
            self.stepsPadded = stepsPadded
            self.motionActive = motionActive
            self.recoveredAt = recoveredAt
            self.stage = stage
            self.tag = tag
        }
    }

    struct RecoveryBest: Codable, Hashable {
        var weekday: String
        var minutes: Int
    }

    var dayKey: String
    /// 04:00 local.
    var dayStart: Date
    /// Generation time. Never Date() inside the engine.
    var now: Date
    /// The user's recap time on this day, default 20:00 local.
    var recapTime: Date
    /// Seeds the copy variants together with dayKey.
    var userId: String
    /// Apple's daily resting values, oldest first, up to 7. Empty falls back to 65.
    var restingHistory: [Int]
    var elevatedMargin: Int
    var elevatedFloor: Int
    var coverage: Double
    var awakeTrackedHours: Double
    var coverageYesterday: Double?
    var runs: [Run]
    var heartRate: [HeartRateSample]
    var steps: [Steps]
    var workouts: [Workout]
    var exercise: [Interval]
    var activeEnergyKcal: Double?
    var sleep: [SleepSample]
    var night: Night?
    var hrv: [HRVReading]
    /// Median of the previous 7 nights' medians; nil under 3 nights.
    var hrvBaseline: Double?
    /// Mean asleep hours over the previous 6 nights; nil under 3 nights.
    var sleepWeekMeanHours: Double?
    var recoveryMedian7d: Double?
    var recoveryBest7d: RecoveryBest?
    var baselineNights: Int
    var recapDays: Int
    var calendarAccess: CalendarAccess
    var caffeine: [Caffeine]
    /// The layer's precomputed calmest moment; nil means derive from `heartRate`.
    var calmest: DayRecap.Calmest?
    /// Suggestion rules shown on the previous days, newest first.
    var previousSuggestions: [RecapSuggestion.Rule]
    /// The local crisis line; nil renders the number-free footer. Never a
    /// number by default: the app layer passes "988" for the US and Canada
    /// only, from the region table (RECAP 6.9).
    var crisisNumber: String?

    init(dayKey: String, dayStart: Date, now: Date, recapTime: Date, userId: String = "",
         restingHistory: [Int] = [], elevatedMargin: Int = 25, elevatedFloor: Int = 80,
         coverage: Double, awakeTrackedHours: Double, coverageYesterday: Double? = nil,
         runs: [Run] = [], heartRate: [HeartRateSample] = [], steps: [Steps] = [],
         workouts: [Workout] = [], exercise: [Interval] = [], activeEnergyKcal: Double? = nil,
         sleep: [SleepSample] = [], night: Night? = nil, hrv: [HRVReading] = [],
         hrvBaseline: Double? = nil, sleepWeekMeanHours: Double? = nil,
         recoveryMedian7d: Double? = nil, recoveryBest7d: RecoveryBest? = nil,
         baselineNights: Int = 7, recapDays: Int = 7,
         calendarAccess: CalendarAccess = CalendarAccess(), caffeine: [Caffeine] = [],
         calmest: DayRecap.Calmest? = nil, previousSuggestions: [RecapSuggestion.Rule] = [],
         crisisNumber: String? = nil) {
        self.dayKey = dayKey
        self.dayStart = dayStart
        self.now = now
        self.recapTime = recapTime
        self.userId = userId
        self.restingHistory = restingHistory
        self.elevatedMargin = elevatedMargin
        self.elevatedFloor = elevatedFloor
        self.coverage = coverage
        self.awakeTrackedHours = awakeTrackedHours
        self.coverageYesterday = coverageYesterday
        self.runs = runs
        self.heartRate = heartRate
        self.steps = steps
        self.workouts = workouts
        self.exercise = exercise
        self.activeEnergyKcal = activeEnergyKcal
        self.sleep = sleep
        self.night = night
        self.hrv = hrv
        self.hrvBaseline = hrvBaseline
        self.sleepWeekMeanHours = sleepWeekMeanHours
        self.recoveryMedian7d = recoveryMedian7d
        self.recoveryBest7d = recoveryBest7d
        self.baselineNights = baselineNights
        self.recapDays = recapDays
        self.calendarAccess = calendarAccess
        self.caffeine = caffeine
        self.calmest = calmest
        self.previousSuggestions = previousSuggestions
        self.crisisNumber = crisisNumber
    }
}

/// The ten daily types (RECAP 5), awarded first match wins in this order.
enum DayType: String, Codable, Hashable, CaseIterable {
    case frayed, nightShift, meetingSurvivor, slowBurner, runningOnFumes
    case bouncedBack, zenMaster, cardioOnly, quietDay, justAWeekday

    /// Everything the classifier looks at, so it can be tested without a recap.
    struct Facts: Hashable {
        var stillSpikes: Int
        var load: Int
        var awakeInBedSpikes: Int
        var wasoMinutes: Int
        var calendarOn: Bool
        /// Still spikes labelled with an event of 2 or more people.
        var meetingSpikes: Int
        /// Still spikes labelled with any event.
        var labelledSpikes: Int
        /// A still spike with 45 or more elevated minutes and magnitude under 40.
        var hasSimmer: Bool
        var stillElevatedMinutes: Int
        var recoveryMedian: Double?
        var allRecoveriesKnown: Bool
        var asleepHours: Double?
        var coverage: Double
        var awakeTrackedHours: Double
        var hrvNight: Double?
        var hrvBaseline: Double?
        var longestWorkoutMinutes: Int
        var exerciseMinutes: Int
        var activeEnergyKcal: Double?

        init(stillSpikes: Int = 0, load: Int = 0, awakeInBedSpikes: Int = 0, wasoMinutes: Int = 0,
             calendarOn: Bool = false, meetingSpikes: Int = 0, labelledSpikes: Int = 0,
             hasSimmer: Bool = false, stillElevatedMinutes: Int = 0, recoveryMedian: Double? = nil,
             allRecoveriesKnown: Bool = false, asleepHours: Double? = nil, coverage: Double = 1,
             awakeTrackedHours: Double = 14, hrvNight: Double? = nil, hrvBaseline: Double? = nil,
             longestWorkoutMinutes: Int = 0, exerciseMinutes: Int = 0, activeEnergyKcal: Double? = nil) {
            self.stillSpikes = stillSpikes
            self.load = load
            self.awakeInBedSpikes = awakeInBedSpikes
            self.wasoMinutes = wasoMinutes
            self.calendarOn = calendarOn
            self.meetingSpikes = meetingSpikes
            self.labelledSpikes = labelledSpikes
            self.hasSimmer = hasSimmer
            self.stillElevatedMinutes = stillElevatedMinutes
            self.recoveryMedian = recoveryMedian
            self.allRecoveriesKnown = allRecoveriesKnown
            self.asleepHours = asleepHours
            self.coverage = coverage
            self.awakeTrackedHours = awakeTrackedHours
            self.hrvNight = hrvNight
            self.hrvBaseline = hrvBaseline
            self.longestWorkoutMinutes = longestWorkoutMinutes
            self.exerciseMinutes = exerciseMinutes
            self.activeEnergyKcal = activeEnergyKcal
        }
    }

    /// Coverage and awake hours a day needs before any type is awarded.
    static let minimumCoverage = 0.5
    static let minimumAwakeHours = 8.0

    static func classify(_ f: Facts) -> DayType {
        if f.stillSpikes >= 5 && f.load >= 65 {
            return .frayed
        }
        if f.awakeInBedSpikes >= 2 || (f.awakeInBedSpikes >= 1 && f.wasoMinutes >= 45) {
            return .nightShift
        }
        if f.calendarOn && f.meetingSpikes >= 2 && f.stillSpikes > 0
            && Double(f.labelledSpikes) >= 0.5 * Double(f.stillSpikes) {
            return .meetingSurvivor
        }
        let slowRecovery = f.stillSpikes >= 2 && (f.recoveryMedian ?? 0) >= 20
        if f.hasSimmer || f.stillElevatedMinutes >= 90 || slowRecovery {
            return .slowBurner
        }
        if let asleep = f.asleepHours, asleep <= 5.5, f.stillSpikes <= 3 {
            return .runningOnFumes
        }
        if f.stillSpikes >= 2, f.allRecoveriesKnown, let median = f.recoveryMedian, median <= 8, f.load <= 50 {
            return .bouncedBack
        }
        var restored = (f.asleepHours ?? 0) >= 7
        if let night = f.hrvNight, let baseline = f.hrvBaseline, night >= baseline {
            restored = true
        }
        if f.coverage >= 0.7 && f.awakeTrackedHours >= 12 && f.stillSpikes == 0
            && f.awakeInBedSpikes == 0 && restored {
            return .zenMaster
        }
        let moved = f.longestWorkoutMinutes >= 20 || f.exerciseMinutes >= 30 || (f.activeEnergyKcal ?? 0) >= 500
        if moved && f.stillSpikes <= 1 && f.load <= 40 {
            return .cardioOnly
        }
        if f.stillSpikes <= 1 {
            return .quietDay
        }
        return .justAWeekday
    }
}

/// One suggestion per recap, never medical (RECAP 6.8).
struct RecapSuggestion: Codable, Hashable {
    enum Rule: String, Codable, Hashable, CaseIterable {
        case breathing, brokenNight, earlierBed, walk, meetingSurvivor, cardioOnly, noNotes, nothingToFix
    }

    /// Authors and year only; the paper sits behind the link.
    struct Source: Codable, Hashable {
        let citation: String
        let url: String

        static let balban2023 = Source(citation: "Balban et al. 2023", url: "https://doi.org/10.1016/j.xcrm.2022.100895")
        static let espie2006 = Source(citation: "Espie et al. 2006", url: "https://doi.org/10.1016/j.smrv.2006.03.002")
        static let watson2015 = Source(citation: "Watson et al. 2015", url: "https://doi.org/10.5665/sleep.4716")
        static let ensari2015 = Source(citation: "Ensari et al. 2015", url: "https://doi.org/10.1002/da.22370")
    }

    let rule: Rule
    let text: String
    let source: Source?
}

/// The generated day: every number the view, the share card and the
/// trophies read, plus the final strings. Never carries raw samples or
/// leaves the device except through the fields RECAP 9 allows.
struct DayRecap: Codable, Hashable {
    enum Bucket: String, Codable, Hashable {
        case inBed, workout, moving, still
    }

    enum InBedKind: String, Codable, Hashable {
        case awake, asleep
    }

    enum Relation: String, Codable, Hashable {
        /// Recovered 10+ min before the event ended.
        case leftBefore
        /// Spiked 5+ min before the event started.
        case inItBefore
        /// Recovered 10+ min after the event ended.
        case stayedAfter
        case cameDownWithIt
    }

    struct Label: Codable, Hashable {
        let eventId: String
        let people: Int
        /// Only with the "show event titles" switch on.
        let title: String?
        let eventStart: Date
        let eventEnd: Date
        let relation: Relation
        /// Lead, early-by or stayed minutes; 0 for cameDownWithIt.
        let relationMinutes: Int
    }

    struct Spike: Codable, Hashable {
        let id: String
        let start: Date
        let end: Date
        let peakAt: Date
        let peak: Int
        let resting: Int
        let magnitude: Int
        let elevatedMinutes: Int
        let stepDensity: Double
        let bucket: Bucket
        let inBedKind: InBedKind?
        let recoveredAt: Date?
        let recoveryMinutes: Int?
        let label: Label?
        var tag: SpikeTag?

        var isLongStretch: Bool {
            return elevatedMinutes >= RecapEngine.longStretchMinutes
        }
    }

    /// The protocol-free seam for trophies and week logs.
    struct Counts: Codable, Hashable {
        var workout: Int
        var moving: Int
        var still: Int
        var inBedAwake: Int
        var inBedAsleep: Int
        /// Still spikes the user put a word on.
        var noticed: Int
        /// Still spikes that came down within 10 min of the peak.
        var bouncedBack: Int

        static let zero = Counts(workout: 0, moving: 0, still: 0, inBedAwake: 0, inBedAsleep: 0, noticed: 0, bouncedBack: 0)

        /// Every daytime spike: the headline number.
        var daytime: Int {
            return workout + moving + still
        }
    }

    enum LoadBand: String, Codable, Hashable, CaseIterable {
        case light, moderate, loaded, heavy, runningHot

        static func band(for total: Int) -> LoadBand {
            switch total {
            case ..<21: return .light
            case 21..<41: return .moderate
            case 41..<61: return .loaded
            case 61..<81: return .heavy
            default: return .runningHot
            }
        }

        var label: String {
            switch self {
            case .light: return "Light"
            case .moderate: return "Moderate"
            case .loaded: return "Loaded"
            case .heavy: return "Heavy"
            case .runningHot: return "Running hot"
            }
        }
    }

    struct Load: Codable, Hashable {
        let s: Double
        let h: Double?
        let d: Double?
        let total: Int
        let band: LoadBand
        /// Sleep debt in hours, kept for the suggestion rules.
        let debtHours: Double
        /// A part was missing or the Watch was on under half the day.
        let partial: Bool
        let firstWeek: Bool
        let estimated: Bool
    }

    enum Comparison: String, Codable, Hashable {
        case faster, aboutTheSame, slower
    }

    struct Recovery: Codable, Hashable {
        /// nil when no still spike had a known recovery.
        let median: Double?
        let median7d: Double?
        let best7d: RecapInput.RecoveryBest?
        let knownCount: Int
        let vsWeek: Comparison?
    }

    struct Calmest: Codable, Hashable {
        var at: Date
        var bpm: Int
    }

    /// One minute of the day's heart rate, the highest reading in it. Kept
    /// on this iPhone for the day chart and spike detail; never posted.
    struct Beat: Codable, Hashable {
        let at: Date
        let bpm: Int
    }

    enum HRVState: String, Codable, Hashable {
        case aboutUsual, lower, higher, noBaseline

        var label: String {
            switch self {
            case .aboutUsual: return "about your usual"
            case .lower: return "lower than your week"
            case .higher: return "higher than your week"
            case .noBaseline: return "no baseline yet"
            }
        }
    }

    struct LastNight: Codable, Hashable {
        let start: Date
        let end: Date
        let asleepMinutes: Int
        let awakeMinutes: Int
        let awakenings: Int
        let lowHR: Int?
        let hrvNight: Double?
        let hrvBaseline: Double?
        let hrvState: HRVState
        let inBed: [Spike]

        var asleepHours: Double {
            return Double(asleepMinutes) / 60
        }

        var isShort: Bool {
            return asleepHours <= 5.5
        }
    }

    enum TypeStatus: String, Codable, Hashable {
        case awarded, pending, thinCoverage, notWorn
    }

    enum AddOn: String, Codable, Hashable {
        case caffeineCurve
    }

    let dayKey: String
    let generatedAt: Date
    let seed: UInt64
    let coverage: Double
    let awakeTrackedHours: Double
    let restingHR: Int
    let restingIsFallback: Bool
    let threshold: Int
    let elevatedMargin: Int
    /// Every bucket, ordered by start.
    var spikes: [Spike]
    var counts: Counts
    let load: Load?
    let recovery: Recovery?
    let calmest: Calmest?
    let lastNight: LastNight?
    let type: DayType?
    let typeStatus: TypeStatus
    let addOns: [AddOn]
    let suggestion: RecapSuggestion?
    /// True before the user's recap time: the day so far.
    let isSoFar: Bool
    let firstWeek: Bool
    var text: RecapText
    /// Last night's start (or 04:00) to generation time, one per minute.
    /// nil on recaps saved before the chart existed.
    var beats: [Beat]? = nil

    var isNotWorn: Bool {
        return typeStatus == .notWorn
    }

    var stillSpikes: [Spike] {
        return spikes.filter { $0.bucket == .still }
    }
}

enum RecapEngine {
    static let fallbackRestingHR = 65
    /// Steps per 10 min at or above which a run is "moving" (RECAP 2.3).
    static let stepDensityLimit: Double = 20
    static let paddingSeconds: TimeInterval = 5 * 60
    static let coolDownSeconds: TimeInterval = 10 * 60
    /// Recovery target is resting + 10, searched for an hour after the peak.
    static let recoveryMargin = 10
    static let recoverySearchSeconds: TimeInterval = 60 * 60
    static let longStretchMinutes = 45
    static let bouncedBackMinutes = 10
    static let sleepGapSeconds: TimeInterval = 30 * 60
    static let awakeningMinimumSeconds: TimeInterval = 2 * 60
    static let caffeineMinimumMg: Double = 50
    static let caffeineWindowMinutes = 15.0...90.0

    static func generate(_ input: RecapInput, calendar: Calendar) -> DayRecap {
        return generate(input, calendar: calendar, picker: .seeded(userId: input.userId, dayKey: input.dayKey))
    }

    static func generate(_ input: RecapInput, calendar: Calendar, picker: RecapCopy.Picker) -> DayRecap {
        let (resting, restingIsFallback) = restingHR(history: input.restingHistory)
        let threshold = max(resting + input.elevatedMargin, input.elevatedFloor)
        let isSoFar = input.now < input.recapTime
        let firstWeek = input.baselineNights < 3 || input.recapDays < 3
        let night = input.night ?? self.night(from: input.sleep, heartRate: input.heartRate,
                                              dayStart: input.dayStart, calendar: calendar)

        if input.coverage <= 0 {
            var recap = DayRecap(
                dayKey: input.dayKey, generatedAt: input.now, seed: picker.seed,
                coverage: 0, awakeTrackedHours: 0, restingHR: resting, restingIsFallback: restingIsFallback,
                threshold: threshold, elevatedMargin: input.elevatedMargin, spikes: [], counts: .zero,
                load: nil, recovery: nil, calmest: nil, lastNight: nil, type: nil, typeStatus: .notWorn,
                addOns: [], suggestion: nil, isSoFar: isSoFar, firstWeek: firstWeek, text: .empty
            )
            recap.text = RecapCopy.render(recap, input: input, calendar: calendar, picker: picker)
            return recap
        }

        let runs = input.runs.sorted { $0.start < $1.start }
        let spikes = runs.map { spike(from: $0, input: input, resting: resting, night: night) }
        let still = spikes.filter { $0.bucket == .still }
        let inBed = spikes.filter { $0.bucket == .inBed }

        let counts = DayRecap.Counts(
            workout: spikes.filter { $0.bucket == .workout }.count,
            moving: spikes.filter { $0.bucket == .moving }.count,
            still: still.count,
            inBedAwake: inBed.filter { $0.inBedKind == .awake }.count,
            inBedAsleep: inBed.filter { $0.inBedKind == .asleep }.count,
            noticed: still.filter { $0.tag != nil }.count,
            bouncedBack: still.filter { ($0.recoveryMinutes ?? Int.max) <= bouncedBackMinutes }.count
        )

        let hrvNight = self.hrvNight(readings: input.hrv, night: night)
        let lastNight: DayRecap.LastNight? = night.map { n in
            DayRecap.LastNight(
                start: n.start, end: n.end, asleepMinutes: n.asleepMinutes, awakeMinutes: n.awakeMinutes,
                awakenings: n.awakenings, lowHR: n.lowHR, hrvNight: hrvNight, hrvBaseline: input.hrvBaseline,
                hrvState: hrvState(night: hrvNight, baseline: input.hrvBaseline), inBed: inBed
            )
        }

        let load = self.load(
            stillMagnitudes: still.map { $0.magnitude }, hrvNight: hrvNight, hrvBaseline: input.hrvBaseline,
            asleepHours: lastNight?.asleepHours, sleepWeekMeanHours: input.sleepWeekMeanHours,
            thinCoverage: input.coverage < DayType.minimumCoverage, firstWeek: firstWeek, estimated: restingIsFallback
        )

        let known = still.compactMap { $0.recoveryMinutes }.map { Double($0) }
        var recovery: DayRecap.Recovery? = nil
        if !still.isEmpty {
            let med = median(known)
            var vsWeek: DayRecap.Comparison? = nil
            if let m = med, let week = input.recoveryMedian7d {
                if m <= week - 5 {
                    vsWeek = .faster
                } else if m >= week + 5 {
                    vsWeek = .slower
                } else {
                    vsWeek = .aboutTheSame
                }
            }
            recovery = DayRecap.Recovery(median: med, median7d: input.recoveryMedian7d,
                                         best7d: input.recoveryBest7d, knownCount: known.count, vsWeek: vsWeek)
        }

        let calmest = input.calmest ?? self.calmest(from: input.heartRate, night: night,
                                                     dayStart: input.dayStart, now: input.now)

        let typeStatus: DayRecap.TypeStatus
        var type: DayType? = nil
        let enoughWatch = input.coverage >= DayType.minimumCoverage && input.awakeTrackedHours >= DayType.minimumAwakeHours
        if enoughWatch {
            typeStatus = .awarded
            let facts = DayType.Facts(
                stillSpikes: still.count,
                load: load.total,
                awakeInBedSpikes: counts.inBedAwake,
                wasoMinutes: night?.awakeMinutes ?? 0,
                calendarOn: input.calendarAccess.access,
                meetingSpikes: still.filter { ($0.label?.people ?? 0) >= 2 }.count,
                labelledSpikes: still.filter { $0.label != nil }.count,
                hasSimmer: still.contains { $0.isLongStretch && $0.magnitude < 40 },
                stillElevatedMinutes: still.reduce(0) { $0 + $1.elevatedMinutes },
                recoveryMedian: recovery?.median,
                allRecoveriesKnown: !still.isEmpty && known.count == still.count,
                asleepHours: lastNight?.asleepHours,
                coverage: input.coverage,
                awakeTrackedHours: input.awakeTrackedHours,
                hrvNight: hrvNight,
                hrvBaseline: input.hrvBaseline,
                longestWorkoutMinutes: input.workouts.map { minutes($0.start, $0.end) }.max() ?? 0,
                exerciseMinutes: input.exercise.reduce(0) { $0 + minutes($1.start, $1.end) },
                activeEnergyKcal: input.activeEnergyKcal
            )
            type = DayType.classify(facts)
        } else if isSoFar {
            typeStatus = .pending
        } else {
            typeStatus = .thinCoverage
        }

        var addOns: [DayRecap.AddOn] = []
        if caffeineCurve(still: still, caffeine: input.caffeine) {
            addOns.append(.caffeineCurve)
        }

        let suggestion = self.suggestion(
            still: still.count, load: load, wasoMinutes: night?.awakeMinutes ?? 0,
            awakeInBed: counts.inBedAwake, asleepHours: lastNight?.asleepHours,
            recoveryMedian: recovery?.median, type: type, previous: input.previousSuggestions, picker: picker
        )

        var recap = DayRecap(
            dayKey: input.dayKey, generatedAt: input.now, seed: picker.seed,
            coverage: input.coverage, awakeTrackedHours: input.awakeTrackedHours,
            restingHR: resting, restingIsFallback: restingIsFallback, threshold: threshold,
            elevatedMargin: input.elevatedMargin, spikes: spikes, counts: counts, load: load,
            recovery: recovery, calmest: calmest, lastNight: lastNight, type: type, typeStatus: typeStatus,
            addOns: addOns, suggestion: suggestion, isSoFar: isSoFar, firstWeek: firstWeek, text: .empty
        )
        recap.text = RecapCopy.render(recap, input: input, calendar: calendar, picker: picker)
        recap.beats = beats(from: input.heartRate + runs.flatMap { $0.samples },
                            start: night.map { min($0.start, input.dayStart) } ?? input.dayStart, end: input.now)
        return recap
    }

    /// The highest reading in each minute of [start, end], oldest first.
    static func beats(from samples: [RecapInput.HeartRateSample], start: Date, end: Date) -> [DayRecap.Beat] {
        var highest: [Int: DayRecap.Beat] = [:]
        for sample in samples where sample.date >= start && sample.date <= end {
            let minute = Int(sample.date.timeIntervalSinceReferenceDate / 60)
            if sample.bpm > highest[minute]?.bpm ?? Int.min {
                highest[minute] = DayRecap.Beat(at: Date(timeIntervalSinceReferenceDate: TimeInterval(minute * 60)), bpm: sample.bpm)
            }
        }
        return highest.values.sorted { $0.at < $1.at }
    }

    // MARK: Resting and thresholds

    /// Median of the last 7 daily values (3 or more), else the newest, else 65.
    static func restingHR(history: [Int]) -> (value: Int, isFallback: Bool) {
        let recent = Array(history.suffix(7))
        if recent.count >= 3, let med = median(recent.map { Double($0) }) {
            return (Int(med.rounded()), false)
        }
        if let newest = recent.last {
            return (newest, false)
        }
        return (fallbackRestingHR, true)
    }

    // MARK: Spikes

    static func spike(from run: RecapInput.Run, input: RecapInput, resting: Int, night: RecapInput.Night?) -> DayRecap.Spike {
        let end = max(run.end, run.start)
        let paddedStart = run.start.addingTimeInterval(-paddingSeconds)
        let paddedEnd = end.addingTimeInterval(paddingSeconds)
        let stepCount = run.stepsPadded ?? steps(from: paddedStart, to: paddedEnd, samples: input.steps)
        let density = stepCount / (paddedEnd.timeIntervalSince(paddedStart) / 600)
        let elevatedMinutes = minutes(run.start, end)
        let recoveredAt = run.recoveredAt ?? self.recoveredAt(samples: run.samples + input.heartRate,
                                                               peakAt: run.peakAt, resting: resting)
        let recoveryMinutes = recoveredAt.map { minutes(run.peakAt, $0) }

        var bucket: DayRecap.Bucket
        var inBedKind: DayRecap.InBedKind? = nil
        // A workout outranks the sleep window: the detector never lets workout
        // samples reach run-finding (RECAP 2.2), and Apple's sleep session can
        // close a few minutes after an early ride starts.
        if input.workouts.contains(where: { overlaps(run.start, end, $0.start, $0.end.addingTimeInterval(coolDownSeconds)) }) {
            bucket = .workout
        } else if let n = night, run.start >= n.start, run.start <= n.end {
            bucket = .inBed
            inBedKind = self.inBedKind(run, sleep: input.sleep)
        } else if density >= stepDensityLimit || run.motionActive
                    || run.samples.contains(where: { $0.motion == .active })
                    || input.exercise.contains(where: { overlaps(run.start, end, $0.start, $0.end) }) {
            bucket = .moving
        } else {
            bucket = .still
        }

        let label = bucket == .still
            ? self.label(start: run.start, end: end, recoveredAt: recoveredAt, access: input.calendarAccess)
            : nil

        return DayRecap.Spike(
            id: run.id, start: run.start, end: end, peakAt: run.peakAt, peak: run.peak, resting: resting,
            magnitude: run.peak - resting, elevatedMinutes: elevatedMinutes, stepDensity: density,
            bucket: bucket, inBedKind: inBedKind, recoveredAt: recoveredAt, recoveryMinutes: recoveryMinutes,
            label: label, tag: run.tag
        )
    }

    static func inBedKind(_ run: RecapInput.Run, sleep: [RecapInput.SleepSample]) -> DayRecap.InBedKind {
        if let stage = run.stage {
            return stage == .awake ? .awake : .asleep
        }
        let from = run.peakAt.addingTimeInterval(-paddingSeconds)
        let to = run.peakAt.addingTimeInterval(paddingSeconds)
        let nearAwake = sleep.contains { $0.stage == .awake && overlaps(from, to, $0.start, $0.end) }
        return nearAwake ? .awake : .asleep
    }

    /// First reading after the peak at or under resting + 10, within an hour.
    static func recoveredAt(samples: [RecapInput.HeartRateSample], peakAt: Date, resting: Int) -> Date? {
        let target = resting + recoveryMargin
        let limit = peakAt.addingTimeInterval(recoverySearchSeconds)
        return samples
            .filter { $0.date > peakAt && $0.date <= limit && $0.bpm <= target }
            .map { $0.date }
            .min()
    }

    /// Proportional overlap, as Romp's Detector.steps.
    static func steps(from start: Date, to end: Date, samples: [RecapInput.Steps]) -> Double {
        var total = 0.0
        for s in samples {
            let duration = s.end.timeIntervalSince(s.start)
            if duration <= 0 {
                if s.start >= start && s.start < end {
                    total += s.count
                }
                continue
            }
            let overlap = min(end, s.end).timeIntervalSince(max(start, s.start))
            if overlap > 0 {
                total += s.count * overlap / duration
            }
        }
        return total
    }

    static func label(start: Date, end: Date, recoveredAt: Date?, access: RecapInput.CalendarAccess) -> DayRecap.Label? {
        guard access.access else {
            return nil
        }
        let windowStart = start.addingTimeInterval(-coolDownSeconds)
        let candidates = access.events.filter { e in
            let duration = e.end.timeIntervalSince(e.start)
            return !e.isAllDay && !e.isCanceled && !e.isDeclined
                && duration >= 5 * 60 && duration <= 4 * 60 * 60
                && overlaps(windowStart, end, e.start, e.end)
        }
        func overlapSeconds(_ e: RecapInput.Event) -> TimeInterval {
            return min(end, e.end).timeIntervalSince(max(windowStart, e.start))
        }
        let ranked = candidates.sorted { a, b in
            let oa = overlapSeconds(a), ob = overlapSeconds(b)
            if oa != ob { return oa > ob }
            if a.people != b.people { return a.people > b.people }
            return a.start < b.start
        }
        guard let event = ranked.first else {
            return nil
        }

        var relation = DayRecap.Relation.cameDownWithIt
        var relationMinutes = 0
        if let r = recoveredAt, r < event.end.addingTimeInterval(-coolDownSeconds) {
            relation = .leftBefore
            relationMinutes = minutes(r, event.end)
        } else if start <= event.start.addingTimeInterval(-paddingSeconds) {
            relation = .inItBefore
            relationMinutes = minutes(start, event.start)
        } else if let r = recoveredAt, r >= event.end.addingTimeInterval(coolDownSeconds) {
            relation = .stayedAfter
            relationMinutes = minutes(event.end, r)
        }
        return DayRecap.Label(
            eventId: event.id, people: max(0, event.people), title: access.showTitles ? event.title : nil,
            eventStart: event.start, eventEnd: event.end, relation: relation, relationMinutes: relationMinutes
        )
    }

    // MARK: Night

    /// The longest sleep session ending between 00:00 and 14:00 on the recap
    /// day, samples grouped when gaps are 30 min or less (RECAP 1).
    static func night(from sleep: [RecapInput.SleepSample], heartRate: [RecapInput.HeartRateSample],
                      dayStart: Date, calendar: Calendar) -> RecapInput.Night? {
        let staged = sleep.filter { $0.stage != .inBed }.sorted { $0.start < $1.start }
        guard !staged.isEmpty else {
            return nil
        }
        var sessions: [[RecapInput.SleepSample]] = []
        var current: [RecapInput.SleepSample] = []
        var currentEnd = Date.distantPast
        for s in staged {
            if !current.isEmpty && s.start.timeIntervalSince(currentEnd) > sleepGapSeconds {
                sessions.append(current)
                current = []
            }
            current.append(s)
            currentEnd = max(currentEnd, s.end)
        }
        sessions.append(current)

        let midnight = dayStart.addingTimeInterval(-4 * 60 * 60)
        let latestEnd = midnight.addingTimeInterval(14 * 60 * 60)
        let candidates = sessions.filter { session in
            let end = session.map { $0.end }.max() ?? Date.distantPast
            return end >= midnight && end <= latestEnd
        }
        guard let session = candidates.max(by: { span($0) < span($1) }) else {
            return nil
        }
        let start = session.map { $0.start }.min() ?? dayStart
        let end = session.map { $0.end }.max() ?? dayStart
        let asleep = session.filter { $0.stage.isAsleep }
        let asleepSeconds = asleep.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }

        let awake = session.filter { $0.stage == .awake }.sorted { $0.start < $1.start }
        var stretches: [(Date, Date)] = []
        for a in awake {
            if let last = stretches.last, a.start.timeIntervalSince(last.1) <= 60 {
                stretches[stretches.count - 1].1 = max(last.1, a.end)
            } else {
                stretches.append((a.start, a.end))
            }
        }
        let awakeSeconds = stretches.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) }
        let awakenings = stretches.filter { $0.1.timeIntervalSince($0.0) >= awakeningMinimumSeconds }.count
        let lowHR = heartRate
            .filter { hr in asleep.contains { hr.date >= $0.start && hr.date <= $0.end } }
            .map { $0.bpm }
            .min()

        return RecapInput.Night(
            start: start, end: end, asleepMinutes: Int((asleepSeconds / 60).rounded()),
            awakeMinutes: Int((awakeSeconds / 60).rounded()), awakenings: awakenings, lowHR: lowHR
        )
    }

    private static func span(_ session: [RecapInput.SleepSample]) -> TimeInterval {
        let start = session.map { $0.start }.min() ?? Date.distantPast
        let end = session.map { $0.end }.max() ?? Date.distantPast
        return end.timeIntervalSince(start)
    }

    /// Median SDNN of the readings inside the sleep window; nil without one.
    static func hrvNight(readings: [RecapInput.HRVReading], night: RecapInput.Night?) -> Double? {
        guard let n = night else {
            return nil
        }
        return median(readings.filter { $0.date >= n.start && $0.date <= n.end }.map { $0.sdnn })
    }

    static func hrvState(night: Double?, baseline: Double?) -> DayRecap.HRVState {
        guard let n = night, let b = baseline, b > 0 else {
            return .noBaseline
        }
        let delta = ((n / b - 1) * 100).rounded()
        if delta < -10 {
            return .lower
        }
        if delta > 10 {
            return .higher
        }
        return .aboutUsual
    }

    // MARK: Load

    static func load(stillMagnitudes: [Int], hrvNight: Double?, hrvBaseline: Double?, asleepHours: Double?,
                     sleepWeekMeanHours: Double?, thinCoverage: Bool, firstWeek: Bool, estimated: Bool) -> DayRecap.Load {
        let units = stillMagnitudes.reduce(0.0) { $0 + Double(min($1, 60)) / 25 }
        let s = 50 * min(units / 8, 1)

        var h: Double? = nil
        if let n = hrvNight, let b = hrvBaseline, b > 0 {
            h = 25 * clamp((1 - n / b) / 0.30)
        }

        var d: Double? = nil
        var debt = 0.0
        if let asleep = asleepHours {
            debt = max(0, 7 - asleep) + 0.5 * max(0, 7 - (sleepWeekMeanHours ?? 7))
            d = 25 * clamp(debt / 3)
        }

        let denominator = 50.0 + (h == nil ? 0 : 25) + (d == nil ? 0 : 25)
        let total = Int((100 * (s + (h ?? 0) + (d ?? 0)) / denominator).rounded())
        return DayRecap.Load(
            s: s, h: h, d: d, total: total, band: DayRecap.LoadBand.band(for: total), debtHours: debt,
            partial: thinCoverage || h == nil || d == nil, firstWeek: firstWeek, estimated: estimated
        )
    }

    // MARK: Calmest moment

    /// Lowest 10-min rolling mean of awake, non-active readings outside the
    /// sleep window and the 20 min after it; needs 3 h of awake readings.
    static func calmest(from heartRate: [RecapInput.HeartRateSample], night: RecapInput.Night?,
                        dayStart: Date, now: Date) -> DayRecap.Calmest? {
        let readings = heartRate
            .filter { hr in
                guard hr.date >= dayStart, hr.date <= now, hr.motion != .active else { return false }
                if let n = night, hr.date >= n.start, hr.date <= n.end.addingTimeInterval(20 * 60) {
                    return false
                }
                return true
            }
            .sorted { $0.date < $1.date }
        let bins = Set(readings.map { Int($0.date.timeIntervalSinceReferenceDate / 1800) })
        guard bins.count >= 6 else {
            return nil
        }
        var best: DayRecap.Calmest? = nil
        var bestMean = Double.infinity
        for (i, first) in readings.enumerated() {
            let windowEnd = first.date.addingTimeInterval(10 * 60)
            let window = readings[i...].prefix(while: { $0.date <= windowEnd })
            guard window.count >= 2 else { continue }
            let mean = Double(window.reduce(0) { $0 + $1.bpm }) / Double(window.count)
            if mean < bestMean {
                bestMean = mean
                best = DayRecap.Calmest(at: first.date.addingTimeInterval(5 * 60), bpm: Int(mean.rounded()))
            }
        }
        return best
    }

    // MARK: Add-ons and suggestion

    /// Two or more still spikes each starting 15-90 min after 50 mg or more
    /// of logged caffeine, or tagged Caffeine by the user (RECAP 5.11).
    static func caffeineCurve(still: [DayRecap.Spike], caffeine: [RecapInput.Caffeine]) -> Bool {
        let matched = still.filter { spike in
            if spike.tag == .caffeine {
                return true
            }
            return caffeine.contains { c in
                guard c.mg >= caffeineMinimumMg else { return false }
                let lead = spike.start.timeIntervalSince(c.date) / 60
                return caffeineWindowMinutes.contains(lead)
            }
        }
        return matched.count >= 2
    }

    static func suggestion(still: Int, load: DayRecap.Load?, wasoMinutes: Int, awakeInBed: Int,
                           asleepHours: Double?, recoveryMedian: Double?, type: DayType?,
                           previous: [RecapSuggestion.Rule], picker: RecapCopy.Picker) -> RecapSuggestion {
        let debt = load?.debtHours ?? 0
        var matching: [RecapSuggestion.Rule] = []
        if still >= 3 { matching.append(.breathing) }
        if debt >= 1 && (wasoMinutes >= 30 || awakeInBed >= 1) { matching.append(.brokenNight) }
        if debt >= 1 { matching.append(.earlierBed) }
        if (recoveryMedian ?? 0) >= 20 { matching.append(.walk) }
        if type == .meetingSurvivor { matching.append(.meetingSurvivor) }
        if type == .cardioOnly { matching.append(.cardioOnly) }
        if type == .zenMaster || type == .quietDay { matching.append(.noNotes) }
        matching.append(.nothingToFix)

        // The same suggestion never runs three days in a row.
        let twice: RecapSuggestion.Rule? = previous.count >= 2 && previous[0] == previous[1] ? previous[0] : nil
        let rule = matching.first { $0 != twice } ?? .nothingToFix

        var gapMinutes: Int? = nil
        if let asleep = asleepHours, asleep < 7 {
            gapMinutes = Int((((7 - asleep) * 60) / 5).rounded(.up)) * 5
        }
        return RecapCopy.suggestion(rule: rule, gapMinutes: gapMinutes, picker: picker)
    }

    // MARK: Helpers

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func minutes(_ from: Date, _ to: Date) -> Int {
        return Int((to.timeIntervalSince(from) / 60).rounded())
    }

    static func overlaps(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        return aStart < bEnd && bStart < aEnd
    }

    static func clamp(_ x: Double) -> Double {
        return min(max(x, 0), 1)
    }
}

extension DayRecap {
    /// The trophies' view of this day (Trophies.swift `DayLedger`). Built from
    /// the summary numbers; the recap does not score sleep (RECAP 6.7 leaves
    /// that to Apple), so the coordinator passes `sleepScore` from the night
    /// summary when it has one.
    func ledger(day: Date, recapOpened: Bool, sleepScore: Int? = nil) -> DayLedger {
        return DayLedger(
            day: day,
            worn: !isNotWorn,
            tracked: typeStatus == .awarded,
            stillSpikes: counts.still,
            movingSpikes: counts.moving,
            workoutSpikes: counts.workout,
            nightRises: counts.inBedAwake,
            recoveryMedianMinutes: recovery?.median,
            load: load?.total,
            sleepScore: sleepScore,
            asleepMinutes: lastNight?.asleepMinutes,
            bedtime: lastNight?.start,
            labelledSpikes: stillSpikes.compactMap { spike -> LabelledSpike? in
                guard let label = spike.label else { return nil }
                return LabelledSpike(title: label.title, recoveryMinutes: spike.recoveryMinutes)
            },
            recapOpened: recapOpened
        )
    }
}
