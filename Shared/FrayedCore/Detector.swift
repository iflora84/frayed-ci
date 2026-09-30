import Foundation

/// Apple's HKMetadataKeyHeartRateMotionContext, as the Health layer maps it.
enum MotionContext: String, Codable, Hashable, Sendable {
    case notSet, sedentary, active
}

struct HRSample: Codable, Hashable, Sendable {
    let date: Date
    let bpm: Int
    let motion: MotionContext

    init(date: Date, bpm: Int, motion: MotionContext = .notSet) {
        self.date = date
        self.bpm = bpm
        self.motion = motion
    }
}

struct StepSample: Codable, Hashable, Sendable {
    let start: Date
    let end: Date
    let count: Double

    init(start: Date, end: Date, count: Double) {
        self.start = start
        self.end = end
        self.count = count
    }
}

/// A stretch of raised heart rate, already told apart from a workout, a walk
/// or the night (RECAP 2.5). Times are only as exact as the background
/// samples, a few minutes apart.
struct SpikeCandidate: Codable, Hashable, Identifiable, Sendable {
    let start: Date
    let end: Date
    /// The first reading at the peak.
    let peakAt: Date
    let avgHR: Int
    let peakHR: Int
    let restingHR: Int
    /// Every reading from start to end, low ones in the middle included. A
    /// workout block keeps one reading per minute (its highest).
    let samples: [HRSample]
    /// Readings at or above the threshold.
    let elevatedCount: Int
    /// Steps per 10 minutes over the run padded by 5 minutes each side.
    let stepDensity: Double
    let attribution: Attribution
    /// Only when `attribution == .inBed`.
    let inBed: InBedKind?
    /// Seconds from the peak to the first reading at or under resting + 10;
    /// nil when none came within an hour or before the next spike.
    let recovery: TimeInterval?

    /// Stable across rescans of the same data: SpikeAnswers keys on it.
    var id: String {
        return "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
    }

    var duration: TimeInterval {
        return end.timeIntervalSince(start)
    }

    var magnitude: Int {
        return peakHR - restingHR
    }

    var recoveryMinutes: Int? {
        return recovery.map { Int(($0 / 60).rounded()) }
    }

    /// 0...1, used only to rank labelled moments (see Detector.clarity).
    var clarity: Double {
        return Detector.clarity(peak: peakHR, resting: restingHR, still: attribution.isStill, elevatedCount: elevatedCount)
    }

    /// The moment to save. Pass the user's answer when there is one;
    /// `attributionOverride` is how "Something else" takes a spike out of the
    /// still count. Throws only for a run with no length, which the default
    /// detector never produces (minSamples is 2 and readings are one per
    /// second at most).
    func makeMoment(
        id: UUID = UUID(),
        noticed: Bool? = nil,
        tag: SpikeTag? = nil,
        attributionOverride: Attribution? = nil
    ) throws -> Moment {
        let wholeStart = floor(start.timeIntervalSince1970)
        let points = samples.map {
            HRPoint(offset: Int(floor($0.date.timeIntervalSince1970 - wholeStart)), bpm: $0.bpm)
        }
        return try Moment(
            id: id,
            start: start,
            end: end,
            kind: .spike,
            attribution: attributionOverride ?? attribution,
            inBed: inBed,
            avgHR: avgHR,
            peakHR: peakHR,
            restingHR: restingHR,
            heartRate: points,
            recoverySeconds: recovery.map { Int($0.rounded()) },
            noticed: noticed,
            tag: tag,
            source: .health,
            visibility: .private
        )
    }
}

/// Finds spikes in background heart rate and says what the body was doing.
/// Pure: the HealthKit layer passes the samples in and shows what comes out.
/// It classifies, it never filters: every run of raised heart rate comes back
/// with an attribution, and only the still ones are stress-like.
///
/// Elevated means bpm >= max(resting + 25, 80). Elevated samples no more than
/// `maxGap` apart form one run, so a single low reading between them does not
/// split it. A run is a spike from 2 samples up, with no duration floor and
/// no ceiling (a still run over two hours is "a long stretch"). Readings
/// inside a workout, padded 10 minutes each side, are taken out before
/// run-finding so 1-second workout data cannot fuse with background readings;
/// each workout then comes back as one `.workout` block. A run that starts
/// inside the sleep window is `.inBed`, sub-typed awake or asleep at its
/// peak. A run with 20 or more steps per 10 minutes over its padded window,
/// an `active` motion context or Apple exercise minutes is `.moving`.
/// Everything else is `.still`. Recovery is measured from the peak to the
/// first reading at or under resting + 10 (RECAP 4.3).
struct Detector {
    /// Settings "Spike threshold": Wide +30, Standard +25, Fine +20.
    var elevatedMargin = 25
    /// Guards against a stale or too-low resting estimate.
    var elevatedFloor = 80
    var maxGap: TimeInterval = 6 * 60
    var minSamples = 2
    /// Steps per 10 minutes at which a run is moving rather than still.
    var stepDensityLimit: Double = 20
    /// Each side of the run, for the step density.
    var stepPad: TimeInterval = 5 * 60
    /// Each side of a workout: warm-up and cool-down count as the workout.
    var workoutPad: TimeInterval = 10 * 60
    /// A workout block keeps its highest reading per this interval.
    var workoutSampleInterval: TimeInterval = 60
    /// Recovered means at or under resting + this.
    var recoveryMargin = 10
    /// How long after the peak a recovery reading still counts.
    var recoverySearch: TimeInterval = 60 * 60
    /// An in-bed peak this close to an awake stretch counts as awake.
    var awakePad: TimeInterval = 5 * 60

    init() {}

    /// Peak clearance over the threshold at which clarity's first term is full.
    static let claritySpan = 25.0
    static let clarityMargin = 25

    func candidates(
        heartRate: [HRSample],
        steps: [StepSample],
        workouts: [DateInterval],
        exerciseIntervals: [DateInterval] = [],
        asleepIntervals: [DateInterval] = [],
        sleepWindow: DateInterval? = nil,
        restingHR: Int?,
        window: DateInterval
    ) -> [SpikeCandidate] {
        let resting = Moment.validHeartRate(restingHR) ?? Moment.fallbackRestingHR
        let threshold = max(resting + elevatedMargin, elevatedFloor)
        let samples = Detector.cleaned(heartRate, window: window)
        let night = sleepWindow ?? Detector.span(asleepIntervals)
        let asleep = Detector.merged(asleepIntervals)
        let blocks = Detector.merged(workouts.map { Detector.padded($0, by: workoutPad) })
        let background = samples.filter { sample in !blocks.contains { $0.contains(sample.date) } }

        var found: [Run] = []
        for run in runs(background.filter { $0.bpm >= threshold }) {
            guard run.count >= minSamples, let first = run.first, let last = run.last else {
                continue
            }
            let inside = background.filter { $0.date >= first.date && $0.date <= last.date }
            let density = stepDensity(steps, from: first.date, to: last.date)
            let (peak, peakAt) = Detector.peak(of: inside)
            let attribution: Attribution
            var inBed: InBedKind? = nil
            if let night = night, night.contains(first.date) {
                attribution = .inBed
                inBed = inBedKind(peakAt: peakAt, asleep: asleep, window: night)
            } else if density >= stepDensityLimit
                        || inside.contains(where: { $0.motion == .active })
                        || exerciseIntervals.contains(where: { Detector.overlaps($0.start, $0.end, first.date, last.date) }) {
                attribution = .moving
            } else {
                attribution = .still
            }
            found.append(Run(
                start: first.date, end: last.date, peak: peak, peakAt: peakAt,
                avg: Detector.mean(inside), samples: inside, elevatedCount: run.count,
                stepDensity: density, attribution: attribution, inBed: inBed
            ))
        }

        for block in blocks {
            let inside = samples.filter { block.contains($0.date) }
            let elevated = inside.filter { $0.bpm >= threshold }
            guard elevated.count >= minSamples, let first = elevated.first, let last = elevated.last else {
                continue
            }
            let span = inside.filter { $0.date >= first.date && $0.date <= last.date }
            let (peak, peakAt) = Detector.peak(of: span)
            found.append(Run(
                start: first.date, end: last.date, peak: peak, peakAt: peakAt,
                avg: Detector.mean(span), samples: thinned(span), elevatedCount: elevated.count,
                stepDensity: stepDensity(steps, from: first.date, to: last.date),
                attribution: .workout, inBed: nil
            ))
        }

        found.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        return found.enumerated().map { (index, run) -> SpikeCandidate in
            let next = index + 1 < found.count ? found[index + 1].start : nil
            return SpikeCandidate(
                start: run.start,
                end: run.end,
                peakAt: run.peakAt,
                avgHR: run.avg,
                peakHR: run.peak,
                restingHR: resting,
                samples: run.samples,
                elevatedCount: run.elevatedCount,
                stepDensity: run.stepDensity,
                attribution: run.attribution,
                inBed: run.inBed,
                recovery: recovery(after: run.peakAt, in: samples, resting: resting, before: next)
            )
        }
    }

    private struct Run {
        let start: Date
        let end: Date
        let peak: Int
        let peakAt: Date
        let avg: Int
        let samples: [HRSample]
        let elevatedCount: Int
        let stepDensity: Double
        let attribution: Attribution
        let inBed: InBedKind?
    }

    /// Groups sorted elevated samples; a gap over `maxGap` starts a new run.
    func runs(_ elevated: [HRSample]) -> [[HRSample]] {
        var result: [[HRSample]] = []
        var current: [HRSample] = []
        for sample in elevated {
            if let last = current.last, sample.date.timeIntervalSince(last.date) > maxGap {
                result.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// Steps per 10 minutes over `from...to` padded by `stepPad` each side
    /// (RECAP 2.3). For a 10-minute run that is "steps in the surrounding
    /// 20 minutes, halved".
    func stepDensity(_ samples: [StepSample], from: Date, to: Date) -> Double {
        let paddedFrom = from.addingTimeInterval(-stepPad)
        let paddedTo = to.addingTimeInterval(stepPad)
        let minutes = paddedTo.timeIntervalSince(paddedFrom) / 60
        guard minutes > 0 else {
            return 0
        }
        return Detector.steps(samples, from: paddedFrom, to: paddedTo) * 10 / minutes
    }

    /// Asleep when the readings around the peak (`awakePad` each side,
    /// clipped to the window) sit inside one asleep interval; awake otherwise,
    /// so a rise within five minutes of an awake stretch counts as awake.
    func inBedKind(peakAt: Date, asleep: [DateInterval], window: DateInterval) -> InBedKind {
        let from = max(peakAt.addingTimeInterval(-awakePad), window.start)
        let to = min(peakAt.addingTimeInterval(awakePad), window.end)
        for interval in asleep where interval.start <= from && interval.end >= to {
            return .asleep
        }
        return .awake
    }

    /// Seconds from the peak to the first later reading at or under
    /// resting + `recoveryMargin`, searching at most `recoverySearch` and never
    /// past `limit` (the next spike's start). nil when it never got there:
    /// the person moved, or the next spike came first.
    func recovery(after peakAt: Date, in samples: [HRSample], resting: Int, before limit: Date? = nil) -> TimeInterval? {
        let target = resting + recoveryMargin
        let deadline = peakAt.addingTimeInterval(recoverySearch)
        for sample in samples where sample.date > peakAt {
            if sample.date > deadline {
                return nil
            }
            if let limit = limit, sample.date >= limit {
                return nil
            }
            if sample.bpm <= target {
                return sample.date.timeIntervalSince(peakAt)
            }
        }
        return nil
    }

    /// 0...1, for ranking the labelled moments only; nothing is hidden by it:
    ///
    ///     0.5 * clamp((peak - resting - 25) / 25)
    ///   + 0.3 when sitting still
    ///   + 0.2 when 3 or more elevated readings
    ///
    /// A still spike peaking at resting + 50 with three readings scores 1.
    static func clarity(peak: Int, resting: Int, still: Bool, elevatedCount: Int) -> Double {
        let clearance = clamp(Double(peak - resting - clarityMargin) / claritySpan) * 0.5
        return clearance + (still ? 0.3 : 0) + (elevatedCount >= 3 ? 0.2 : 0)
    }

    /// One reading per `workoutSampleInterval`, the highest in each, so a
    /// 1-second workout series does not swell the moment file. The peak is
    /// always kept.
    func thinned(_ samples: [HRSample]) -> [HRSample] {
        guard workoutSampleInterval > 0, let first = samples.first else {
            return samples
        }
        var result: [HRSample] = []
        var bucket = -1
        for sample in samples {
            let index = Int(floor(sample.date.timeIntervalSince(first.date) / workoutSampleInterval))
            if index != bucket {
                result.append(sample)
                bucket = index
            } else if let last = result.last, sample.bpm > last.bpm {
                result[result.count - 1] = sample
            }
        }
        return result
    }

    private static func clamp(_ value: Double) -> Double {
        return min(max(value, 0), 1)
    }

    /// Inside the window, inside the bpm range, sorted by date; two readings
    /// in the same second keep the higher one.
    static func cleaned(_ samples: [HRSample], window: DateInterval) -> [HRSample] {
        let sorted = samples
            .filter { window.contains($0.date) && Moment.heartRateRange.contains($0.bpm) }
            .sorted { a, b in
                if a.date != b.date {
                    return a.date < b.date
                }
                return a.bpm > b.bpm
            }
        var result: [HRSample] = []
        for sample in sorted {
            if let last = result.last, floor(last.date.timeIntervalSince1970) == floor(sample.date.timeIntervalSince1970) {
                continue
            }
            result.append(sample)
        }
        return result
    }

    static func mean(_ samples: [HRSample]) -> Int {
        guard !samples.isEmpty else {
            return 0
        }
        return Int((Double(samples.reduce(0) { $0 + $1.bpm }) / Double(samples.count)).rounded())
    }

    /// The highest reading and when it was first seen. Expects sorted,
    /// non-empty samples.
    static func peak(of samples: [HRSample]) -> (Int, Date) {
        var best = samples[0]
        for sample in samples.dropFirst() where sample.bpm > best.bpm {
            best = sample
        }
        return (best.bpm, best.date)
    }

    static func padded(_ interval: DateInterval, by pad: TimeInterval) -> DateInterval {
        return DateInterval(start: interval.start.addingTimeInterval(-pad), end: interval.end.addingTimeInterval(pad))
    }

    /// From the earliest start to the latest end; nil when there are none.
    static func span(_ intervals: [DateInterval]) -> DateInterval? {
        guard let first = intervals.map({ $0.start }).min(), let last = intervals.map({ $0.end }).max(), last >= first else {
            return nil
        }
        return DateInterval(start: first, end: last)
    }

    /// Union of overlapping or touching intervals, sorted by start.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Steps inside `from...to`; a sample that straddles the edge counts in
    /// proportion to its overlap.
    static func steps(_ samples: [StepSample], from: Date, to: Date) -> Double {
        var total = 0.0
        for sample in samples {
            let length = sample.end.timeIntervalSince(sample.start)
            if length <= 0 {
                if sample.start >= from && sample.start <= to {
                    total += sample.count
                }
                continue
            }
            let overlap = min(sample.end, to).timeIntervalSince(max(sample.start, from))
            if overlap > 0 {
                total += sample.count * overlap / length
            }
        }
        return total
    }

    /// Strict: ranges that only touch do not overlap.
    static func overlaps(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        return aStart < bEnd && bStart < aEnd
    }
}
