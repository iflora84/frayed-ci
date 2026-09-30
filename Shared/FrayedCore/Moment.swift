import Foundation

enum MomentKind: String, Codable, CaseIterable, Sendable {
    /// A run of raised heart rate the detector found, or one the user logged.
    case spike
    /// A night that qualified on its own (SPEC 1.5), postable by itself.
    case roughNight
    /// The day's recap, one per local day.
    case recap

    var label: String {
        switch self {
        case .spike: return "Spike"
        case .roughNight: return "Rough night"
        case .recap: return "Recap"
        }
    }
}

/// What the body was doing when the heart went up (RECAP 3.1). Only `still`
/// counts toward the headline; the rest stay on the timeline. `other` is
/// never produced by the detector: the user picks it ("Something else") to
/// take a spike out of the still count without deleting it.
enum Attribution: String, Codable, CaseIterable, Sendable {
    case workout, moving, still, inBed, other

    var label: String {
        switch self {
        case .workout: return "Workout"
        case .moving: return "Moving"
        case .still: return "Still"
        case .inBed: return "In bed"
        case .other: return "Something else"
        }
    }

    /// The attribution as it reads inside a sentence ("peak 114 · while still").
    var phrase: String {
        switch self {
        case .workout: return "in a workout"
        case .moving: return "while moving"
        case .still: return "sitting still"
        case .inBed: return "in bed"
        case .other: return "something else"
        }
    }

    var isStill: Bool {
        return self == .still
    }

    /// Workout, moving and still are the daytime buckets the headline counts.
    var isDaytime: Bool {
        return self == .workout || self == .moving || self == .still
    }
}

/// Sub-type of an in-bed spike: the Watch had the person awake (or within
/// five minutes of an awake stretch) at the peak, or asleep. Heart rate
/// climbing during REM is ordinary physiology, so an asleep rise is never a
/// bad thing (RECAP 2.4).
enum InBedKind: String, Codable, CaseIterable, Sendable {
    case awake, asleep
}

/// The user's own word for a spike (RECAP 2.5). The app repeats it verbatim
/// and never adds to it; it is never posted.
enum SpikeTag: String, Codable, CaseIterable, Sendable {
    case meeting, argument, deadline, panic, excited, somethingGood, caffeine, noIdea

    var label: String {
        switch self {
        case .meeting: return "Meeting"
        case .argument: return "Argument"
        case .deadline: return "Deadline"
        case .panic: return "Panic"
        case .excited: return "Excited"
        case .somethingGood: return "Something good"
        case .caffeine: return "Caffeine"
        case .noIdea: return "No idea"
        }
    }
}

enum MomentSource: String, Codable, CaseIterable, Sendable {
    /// Found in background heart rate from Apple Health.
    case health
    /// Typed in ("No Watch that time? Log a moment you felt.").
    case manual
}

enum MomentVisibility: String, Codable, CaseIterable, Sendable {
    case `private`, friends, anonymous
}

/// The calendar event a spike overlapped (RECAP 3.3). Local only: the
/// title never enters a post, a share card or a notification. `people` is
/// the attendee count without the user; 0 is a solo block.
struct CalendarLabel: Codable, Hashable, Sendable {
    var eventID: String?
    var title: String?
    var people: Int
    var eventStart: Date?
    var eventEnd: Date?

    init(eventID: String? = nil, title: String? = nil, people: Int = 0, eventStart: Date? = nil, eventEnd: Date? = nil) {
        self.eventID = eventID
        self.title = Moment.cleanTitle(title)
        self.people = max(people, 0)
        self.eventStart = eventStart
        self.eventEnd = eventEnd
    }

    private enum CodingKeys: String, CodingKey {
        case eventID, title, people, eventStart, eventEnd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            eventID: try? c.decodeIfPresent(String.self, forKey: .eventID),
            title: try? c.decodeIfPresent(String.self, forKey: .title),
            people: (try? c.decodeIfPresent(Int.self, forKey: .people)) ?? 0,
            eventStart: try? c.decodeIfPresent(Date.self, forKey: .eventStart),
            eventEnd: try? c.decodeIfPresent(Date.self, forKey: .eventEnd)
        )
    }
}

enum MomentValidationError: Error, Equatable {
    case endNotAfterStart
    case longerThanMaximum
}

struct Moment: Codable, Identifiable, Hashable, Sendable {
    /// A recap spans a day.
    static let maxDuration: TimeInterval = 24 * 3600
    static let heartRateRange: ClosedRange<Int> = 30...240
    /// Used when Health has no resting heart rate yet (RECAP 1).
    static let fallbackRestingHR = 65

    /// The summary numbers of a recap moment (RECAP 9). Posts and share
    /// cards are built from these alone; everything else stays on the device.
    struct RecapSummary: Codable, Hashable, Sendable {
        static let loadRange: ClosedRange<Int> = 0...100
        static let stripLength = 24

        /// Workout + moving + still; in-bed spikes are never in it.
        var spikeCount: Int
        var stillCount: Int
        var movingCount: Int
        var workoutCount: Int
        /// Still spikes the user put a tag on.
        var noticedCount: Int
        /// 0...100, nil when the Watch was not worn.
        var load: Int?
        /// Median over the still spikes with a known recovery.
        var recoverySeconds: Int?
        var calmestBpm: Int?
        /// Stable day-type id (DayType.rawValue); nil while pending.
        var dayType: String?
        /// Share of 30-minute bins with at least one reading, 0...1.
        var coverage: Double
        /// Hourly peak heart rate from the day's start, 0 where the Watch had
        /// no reading; at most 24 entries. The share card's strip.
        var hourlyPeaks: [Int]

        init(
            spikeCount: Int = 0,
            stillCount: Int = 0,
            movingCount: Int = 0,
            workoutCount: Int = 0,
            noticedCount: Int = 0,
            load: Int? = nil,
            recoverySeconds: Int? = nil,
            calmestBpm: Int? = nil,
            dayType: String? = nil,
            coverage: Double = 0,
            hourlyPeaks: [Int] = []
        ) {
            self.spikeCount = max(spikeCount, 0)
            self.stillCount = max(stillCount, 0)
            self.movingCount = max(movingCount, 0)
            self.workoutCount = max(workoutCount, 0)
            self.noticedCount = max(noticedCount, 0)
            self.load = load.map { min(max($0, RecapSummary.loadRange.lowerBound), RecapSummary.loadRange.upperBound) }
            self.recoverySeconds = recoverySeconds.flatMap { $0 >= 0 ? $0 : nil }
            self.calmestBpm = Moment.validHeartRate(calmestBpm)
            self.dayType = Moment.cleanTitle(dayType)
            self.coverage = min(max(coverage, 0), 1)
            self.hourlyPeaks = hourlyPeaks.prefix(RecapSummary.stripLength).map { Moment.validHeartRate($0) ?? 0 }
        }

        private enum CodingKeys: String, CodingKey {
            case spikeCount, stillCount, movingCount, workoutCount, noticedCount, load
            case recoverySeconds, calmestBpm, dayType, coverage, hourlyPeaks
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                spikeCount: (try? c.decodeIfPresent(Int.self, forKey: .spikeCount)) ?? 0,
                stillCount: (try? c.decodeIfPresent(Int.self, forKey: .stillCount)) ?? 0,
                movingCount: (try? c.decodeIfPresent(Int.self, forKey: .movingCount)) ?? 0,
                workoutCount: (try? c.decodeIfPresent(Int.self, forKey: .workoutCount)) ?? 0,
                noticedCount: (try? c.decodeIfPresent(Int.self, forKey: .noticedCount)) ?? 0,
                load: try? c.decodeIfPresent(Int.self, forKey: .load),
                recoverySeconds: try? c.decodeIfPresent(Int.self, forKey: .recoverySeconds),
                calmestBpm: try? c.decodeIfPresent(Int.self, forKey: .calmestBpm),
                dayType: try? c.decodeIfPresent(String.self, forKey: .dayType),
                coverage: (try? c.decodeIfPresent(Double.self, forKey: .coverage)) ?? 0,
                hourlyPeaks: (try? c.decodeIfPresent([Int].self, forKey: .hourlyPeaks)) ?? []
            )
        }
    }

    /// Last night in numbers (RECAP 1, 2.4). Carried by a rough night and by
    /// every recap.
    struct NightSummary: Codable, Hashable, Sendable {
        static let scoreRange: ClosedRange<Int> = 0...100

        var asleepMinutes: Int
        /// Awake minutes inside the sleep window (WASO).
        var awakeMinutes: Int
        /// Awake stretches of two minutes or more that the Watch caught.
        var awakenings: Int
        /// Lowest background reading while asleep.
        var lowestHR: Int?
        /// 0...100 from duration and awakenings; nil without a sleep session.
        var sleepScore: Int?
        /// In-bed spikes with the person awake at the peak.
        var awakeRises: Int
        /// In-bed spikes with the person asleep at the peak.
        var asleepRises: Int
        /// Median SDNN inside the sleep window, milliseconds.
        var hrvNight: Double?
        /// Median of the previous seven nights' medians, milliseconds.
        var hrvBaseline: Double?

        init(
            asleepMinutes: Int = 0,
            awakeMinutes: Int = 0,
            awakenings: Int = 0,
            lowestHR: Int? = nil,
            sleepScore: Int? = nil,
            awakeRises: Int = 0,
            asleepRises: Int = 0,
            hrvNight: Double? = nil,
            hrvBaseline: Double? = nil
        ) {
            self.asleepMinutes = max(asleepMinutes, 0)
            self.awakeMinutes = max(awakeMinutes, 0)
            self.awakenings = max(awakenings, 0)
            self.lowestHR = Moment.validHeartRate(lowestHR)
            self.sleepScore = sleepScore.map { min(max($0, NightSummary.scoreRange.lowerBound), NightSummary.scoreRange.upperBound) }
            self.awakeRises = max(awakeRises, 0)
            self.asleepRises = max(asleepRises, 0)
            self.hrvNight = hrvNight.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
            self.hrvBaseline = hrvBaseline.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        }

        private enum CodingKeys: String, CodingKey {
            case asleepMinutes, awakeMinutes, awakenings, lowestHR, sleepScore
            case awakeRises, asleepRises, hrvNight, hrvBaseline
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                asleepMinutes: (try? c.decodeIfPresent(Int.self, forKey: .asleepMinutes)) ?? 0,
                awakeMinutes: (try? c.decodeIfPresent(Int.self, forKey: .awakeMinutes)) ?? 0,
                awakenings: (try? c.decodeIfPresent(Int.self, forKey: .awakenings)) ?? 0,
                lowestHR: try? c.decodeIfPresent(Int.self, forKey: .lowestHR),
                sleepScore: try? c.decodeIfPresent(Int.self, forKey: .sleepScore),
                awakeRises: (try? c.decodeIfPresent(Int.self, forKey: .awakeRises)) ?? 0,
                asleepRises: (try? c.decodeIfPresent(Int.self, forKey: .asleepRises)) ?? 0,
                hrvNight: try? c.decodeIfPresent(Double.self, forKey: .hrvNight),
                hrvBaseline: try? c.decodeIfPresent(Double.self, forKey: .hrvBaseline)
            )
        }
    }

    let id: UUID
    let start: Date
    let end: Date
    let kind: MomentKind
    /// Changing it away from `inBed` drops the in-bed sub-type with it.
    var attribution: Attribution {
        didSet {
            if attribution != .inBed {
                inBed = nil
            }
        }
    }
    /// Only ever set on an in-bed spike.
    var inBed: InBedKind? {
        didSet {
            if attribution != .inBed {
                inBed = nil
            }
        }
    }
    let avgHR: Int?
    let peakHR: Int?
    /// Resting heart rate at the time, so magnitude does not drift later.
    let restingHR: Int?
    /// Heart rate over the moment, sorted by offset. Empty for manual logs.
    let heartRate: [HRPoint]
    /// Seconds from the peak to the first reading at or under resting + 10
    /// (RECAP 4.3); nil when the Watch could not tell.
    let recoverySeconds: Int?
    /// "Felt it" / "Didn't notice"; nil until answered.
    var noticed: Bool?
    var tag: SpikeTag?
    /// Never leaves the device.
    var note: String
    /// The user's own title. nil means the auto title is shown.
    var title: String? {
        didSet { title = Moment.cleanTitle(title) }
    }
    let source: MomentSource
    var visibility: MomentVisibility
    /// Local only; never encoded into a post.
    var calendarLabel: CalendarLabel?
    /// Only on a `.recap`; forced nil otherwise.
    var recap: RecapSummary? {
        didSet {
            if kind != .recap {
                recap = nil
            }
        }
    }
    /// Only on a `.roughNight` or `.recap`; forced nil otherwise.
    var night: NightSummary? {
        didSet {
            if !Moment.carriesNight(kind) {
                night = nil
            }
        }
    }

    var duration: TimeInterval {
        return end.timeIntervalSince(start)
    }

    /// Peak above resting; nil without either number.
    var magnitude: Int? {
        guard let peak = peakHR, let resting = restingHR else {
            return nil
        }
        return peak - resting
    }

    /// Dates are truncated to whole seconds so a record survives the ISO 8601
    /// round trip through the store unchanged. Out-of-range heart rates and a
    /// negative recovery become nil. Heart-rate points outside the moment are
    /// dropped, and a missing avgHR or peakHR is filled in from the points.
    /// `inBed`, `recap` and `night` are forced nil when the attribution or
    /// kind does not carry them.
    init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        kind: MomentKind = .spike,
        attribution: Attribution = .still,
        inBed: InBedKind? = nil,
        avgHR: Int? = nil,
        peakHR: Int? = nil,
        restingHR: Int? = nil,
        heartRate: [HRPoint] = [],
        recoverySeconds: Int? = nil,
        noticed: Bool? = nil,
        tag: SpikeTag? = nil,
        note: String = "",
        title: String? = nil,
        source: MomentSource = .manual,
        visibility: MomentVisibility = .private,
        calendarLabel: CalendarLabel? = nil,
        recap: RecapSummary? = nil,
        night: NightSummary? = nil
    ) throws {
        let wholeStart = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970))
        let wholeEnd = Date(timeIntervalSince1970: floor(end.timeIntervalSince1970))
        guard wholeEnd > wholeStart else {
            throw MomentValidationError.endNotAfterStart
        }
        guard wholeEnd.timeIntervalSince(wholeStart) <= Moment.maxDuration else {
            throw MomentValidationError.longerThanMaximum
        }

        let series = HRPoint.normalized(heartRate, duration: wholeEnd.timeIntervalSince(wholeStart))

        self.id = id
        self.start = wholeStart
        self.end = wholeEnd
        self.kind = kind
        self.attribution = attribution
        self.inBed = attribution == .inBed ? inBed : nil
        self.avgHR = Moment.validHeartRate(avgHR) ?? HRPoint.mean(series)
        self.peakHR = Moment.validHeartRate(peakHR) ?? series.map { $0.bpm }.max()
        self.restingHR = Moment.validHeartRate(restingHR)
        self.heartRate = series
        self.recoverySeconds = recoverySeconds.flatMap { $0 >= 0 ? $0 : nil }
        self.noticed = noticed
        self.tag = tag
        self.note = note
        self.title = Moment.cleanTitle(title)
        self.source = source
        self.visibility = visibility
        self.calendarLabel = calendarLabel
        self.recap = kind == .recap ? recap : nil
        self.night = Moment.carriesNight(kind) ? night : nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, kind, attribution, inBed, avgHR, peakHR, restingHR, heartRate
        case recoverySeconds, noticed, tag, note, title, source, visibility, calendarLabel, recap, night
    }

    // Decoding goes through the validating init so a hand-edited or older
    // file can never produce a moment the rest of the app would reject.
    // Only id, start and end are required. Everything else falls back to its
    // default when missing or unreadable, so records from an older or a newer
    // build still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kindName = try? c.decodeIfPresent(String.self, forKey: .kind)
        let attributionName = try? c.decodeIfPresent(String.self, forKey: .attribution)
        let inBedName = try? c.decodeIfPresent(String.self, forKey: .inBed)
        let tagName = try? c.decodeIfPresent(String.self, forKey: .tag)
        let sourceName = try? c.decodeIfPresent(String.self, forKey: .source)
        let visibilityName = try? c.decodeIfPresent(String.self, forKey: .visibility)
        try self.init(
            id: try c.decode(UUID.self, forKey: .id),
            start: try c.decode(Date.self, forKey: .start),
            end: try c.decode(Date.self, forKey: .end),
            kind: kindName.flatMap { MomentKind(rawValue: $0) } ?? .spike,
            attribution: attributionName.flatMap { Attribution(rawValue: $0) } ?? .still,
            inBed: inBedName.flatMap { InBedKind(rawValue: $0) },
            avgHR: try? c.decodeIfPresent(Int.self, forKey: .avgHR),
            peakHR: try? c.decodeIfPresent(Int.self, forKey: .peakHR),
            restingHR: try? c.decodeIfPresent(Int.self, forKey: .restingHR),
            heartRate: (try? c.decodeIfPresent([HRPoint].self, forKey: .heartRate)) ?? [],
            recoverySeconds: try? c.decodeIfPresent(Int.self, forKey: .recoverySeconds),
            noticed: try? c.decodeIfPresent(Bool.self, forKey: .noticed),
            tag: tagName.flatMap { SpikeTag(rawValue: $0) },
            note: (try? c.decodeIfPresent(String.self, forKey: .note)) ?? "",
            title: try? c.decodeIfPresent(String.self, forKey: .title),
            source: sourceName.flatMap { MomentSource(rawValue: $0) } ?? .manual,
            visibility: visibilityName.flatMap { MomentVisibility(rawValue: $0) } ?? .private,
            calendarLabel: try? c.decodeIfPresent(CalendarLabel.self, forKey: .calendarLabel),
            recap: try? c.decodeIfPresent(RecapSummary.self, forKey: .recap),
            night: try? c.decodeIfPresent(NightSummary.self, forKey: .night)
        )
    }

    static func carriesNight(_ kind: MomentKind) -> Bool {
        return kind == .roughNight || kind == .recap
    }

    static func validHeartRate(_ bpm: Int?) -> Int? {
        guard let bpm = bpm, heartRateRange.contains(bpm) else {
            return nil
        }
        return bpm
    }

    static func cleanTitle(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Newest first; ties broken by id so the order is stable across loads.
    static func newestFirst(_ moments: [Moment]) -> [Moment] {
        return moments.sorted { a, b in
            if a.start != b.start {
                return a.start > b.start
            }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
