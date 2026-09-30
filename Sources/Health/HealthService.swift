import Foundation
import HealthKit

enum HealthServiceError: Error, Equatable {
    /// Health data is not available on this device (iPad, some managed devices).
    case unavailable
    /// The iPhone is locked and the Health database is encrypted. Not a real
    /// failure: the coordinator tries again the next time Frayed is opened.
    case protectedDataUnavailable
    /// The user has not been asked for Health access yet.
    case notAuthorized
}

/// A thin HealthKit wrapper, ported from Romp. It reads everything the recap
/// engine wants for one local day and hands it over in RecapInput's types.
/// Nothing here decides anything; Detector finds the runs and RecapEngine
/// writes the day.
final class HealthService: @unchecked Sendable {
    let store = HKHealthStore()

    /// A recap day runs 04:00 to 04:00 local (RECAP 1).
    static let dayStartHour = 4
    /// Sleep is read from the evening before the day so last night is whole.
    static let sleepLookbackHours = 10.0
    /// Nights that feed the HRV and sleep baselines.
    static let baselineNights = 7
    static let coverageBinSeconds: TimeInterval = 30 * 60
    /// Series 12 readings arrive every few seconds; one median reading per
    /// minute keeps both Watch fleets looking the same to the detector.
    static let downsampleSeconds: TimeInterval = 60

    static var isAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }

    private static let bpm = HKUnit.count().unitDivided(by: .minute())
    private static let milligram = HKUnit.gramUnit(with: .milli)

    static var readTypes: Set<HKObjectType> {
        return [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.stepCount),
            HKObjectType.workoutType(),
            HKQuantityType(.appleExerciseTime),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.dietaryCaffeine)
        ]
    }

    init() {}

    // MARK: Authorization

    /// Shows the Health sheet once for every read type. HealthKit never says
    /// whether reading was allowed, so after the sheet the answer is
    /// `authorized` when nothing is left to ask and `unknown` otherwise; a
    /// denied read simply returns no samples.
    func requestAuthorization() async -> HealthStatus {
        guard HealthService.isAvailable else {
            return .unavailable
        }
        do {
            try await store.requestAuthorization(toShare: [], read: HealthService.readTypes)
        } catch {
            return .denied
        }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: HealthService.readTypes)
        return status == .unnecessary ? .authorized : .unknown
    }

    // MARK: Recap input

    /// Everything RecapEngine needs for one local day, already in RecapInput's
    /// types. `day` is any instant on the recap day's calendar date; the day
    /// itself runs 04:00 to 04:00 local. Throws
    /// HealthServiceError.protectedDataUnavailable when the phone is locked.
    func recapInput(day: Date, now: Date, schedule: RecapNotification.Schedule,
                    userId: String, elevatedMargin: Int, previousSuggestions: [RecapSuggestion.Rule],
                    recapDays: Int, calendar: Calendar) async throws -> RecapInput {
        guard HealthService.isAvailable else {
            throw HealthServiceError.unavailable
        }

        let dayStart = HealthService.dayStart(for: day, calendar: calendar)
        let dayKey = HealthService.dayKey(dayStart, calendar: calendar)
        let end = max(now, dayStart)
        let sleepStart = dayStart.addingTimeInterval(-HealthService.sleepLookbackHours * 3600)
        let baselineStart = calendar.date(byAdding: .day, value: -HealthService.baselineNights, to: sleepStart) ?? sleepStart

        let heartRate = try await heartRateSamples(in: DateInterval(start: sleepStart, end: end))
        let sleep = try await unlessNotAsked { try await self.sleepSamples(in: DateInterval(start: baselineStart, end: end)) }
        let restingHistory = try await unlessNotAsked { try await self.restingHistory(before: end) }
        let hrv = try await unlessNotAsked { try await self.hrvReadings(in: DateInterval(start: baselineStart, end: end)) }
        let steps = try await unlessNotAsked { try await self.stepSamples(in: DateInterval(start: sleepStart, end: end)) }
        let workouts = try await unlessNotAsked { try await self.workouts(in: DateInterval(start: sleepStart, end: end)) }
        let exercise = try await unlessNotAsked { try await self.exerciseIntervals(in: DateInterval(start: sleepStart, end: end)) }
        let caffeine = try await unlessNotAsked { try await self.caffeine(in: DateInterval(start: dayStart, end: end)) }
        let activeEnergy = await watchActiveEnergy(in: DateInterval(start: dayStart, end: end))
        let coverageYesterday = try await coverageYesterday(dayStart: dayStart, calendar: calendar)

        let night = RecapEngine.night(from: sleep, heartRate: heartRate, dayStart: dayStart, calendar: calendar)
        let baseline = HealthService.baseline(sleep: sleep, hrv: hrv, dayStart: dayStart, calendar: calendar)
        let todayReadings = heartRate.filter { $0.date >= dayStart && $0.date <= end }
        let bins = HealthService.bins(of: todayReadings, from: dayStart, to: end)
        let awakeBins = bins.filter { bin in
            guard let n = night else { return true }
            return bin.end <= n.start || bin.start >= n.end
        }

        let resting = RecapEngine.restingHR(history: restingHistory).value
        let windowStart = night.map { min($0.start, dayStart) } ?? dayStart
        var detector = Detector()
        detector.elevatedMargin = elevatedMargin
        let candidates = detector.candidates(
            heartRate: heartRate.map { HRSample(date: $0.date, bpm: $0.bpm, motion: MotionContext(rawValue: $0.motion.rawValue) ?? .notSet) },
            steps: steps.map { StepSample(start: $0.start, end: $0.end, count: $0.count) },
            workouts: workouts.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) },
            exerciseIntervals: exercise.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) },
            asleepIntervals: sleep.filter { $0.stage.isAsleep }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) },
            sleepWindow: night.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) },
            restingHR: resting,
            window: DateInterval(start: windowStart, end: end)
        )

        var recapTime = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: dayStart) ?? dayStart
        if recapTime < dayStart {
            recapTime = calendar.date(byAdding: .day, value: 1, to: recapTime) ?? recapTime
        }

        return RecapInput(
            dayKey: dayKey,
            dayStart: dayStart,
            now: now,
            recapTime: recapTime,
            userId: userId,
            restingHistory: restingHistory,
            elevatedMargin: elevatedMargin,
            elevatedFloor: 80,
            coverage: HealthService.coverage(bins: bins, from: dayStart, to: end),
            awakeTrackedHours: Double(awakeBins.count) * HealthService.coverageBinSeconds / 3600,
            coverageYesterday: coverageYesterday,
            runs: candidates.map { HealthService.run(from: $0) },
            heartRate: heartRate,
            steps: steps,
            workouts: workouts,
            exercise: exercise,
            activeEnergyKcal: activeEnergy,
            sleep: sleep.filter { $0.end >= sleepStart },
            night: night,
            hrv: hrv.filter { $0.date >= sleepStart },
            hrvBaseline: baseline.hrv,
            sleepWeekMeanHours: baseline.sleepMeanHours,
            baselineNights: baseline.nights,
            recapDays: recapDays,
            calendarAccess: RecapInput.CalendarAccess(),
            caffeine: caffeine,
            previousSuggestions: previousSuggestions,
            crisisNumber: HealthService.crisisNumber()
        )
    }

    // MARK: Day and coverage

    /// 04:00 local on the calendar day of `day`. The caller picks the recap
    /// day (AppModel.recapDay already moves an early-morning `now` to the
    /// day before), so nothing is shifted here.
    static func dayStart(for day: Date, calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: midnight) ?? midnight
    }

    /// "2026-09-22": the local calendar day of dayStart.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The 30-minute bins between `from` and `to` that hold a reading.
    static func bins(of samples: [RecapInput.HeartRateSample], from: Date, to: Date) -> [DateInterval] {
        var indices = Set<Int>()
        for s in samples where s.date >= from && s.date <= to {
            indices.insert(Int(floor(s.date.timeIntervalSince(from) / coverageBinSeconds)))
        }
        return indices.sorted().map { i in
            DateInterval(start: from.addingTimeInterval(Double(i) * coverageBinSeconds), duration: coverageBinSeconds)
        }
    }

    static func coverage(bins: [DateInterval], from: Date, to: Date) -> Double {
        let total = Int(ceil(to.timeIntervalSince(from) / coverageBinSeconds))
        guard total > 0 else {
            return 0
        }
        return min(1, Double(bins.count) / Double(total))
    }

    /// Yesterday's coverage from a bucketed query rather than a day of
    /// samples; nil when heart rate has not been asked for yet.
    private func coverageYesterday(dayStart: Date, calendar: Calendar) async throws -> Double? {
        guard let start = calendar.date(byAdding: .day, value: -1, to: dayStart) else {
            return nil
        }
        let window = DateInterval(start: start, end: dayStart)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: predicate(for: window)),
            options: .discreteMax,
            anchorDate: window.start,
            intervalComponents: DateComponents(minute: 30)
        )
        let collection: HKStatisticsCollection
        do {
            collection = try await mapped { try await descriptor.result(for: self.store) }
        } catch HealthServiceError.notAuthorized {
            return nil
        }
        let filled = collection.statistics().filter { $0.maximumQuantity() != nil }.count
        let total = Int(ceil(window.duration / HealthService.coverageBinSeconds))
        return total > 0 ? min(1, Double(filled) / Double(total)) : 0
    }

    // MARK: Baselines

    struct Baseline {
        var hrv: Double?
        var sleepMeanHours: Double?
        var nights: Int
    }

    /// The previous seven nights, each grouped the way the engine groups
    /// last night: the median of their HRV medians (3 or more nights) and
    /// the mean of the last six nights' asleep hours (3 or more).
    static func baseline(sleep: [RecapInput.SleepSample], hrv: [RecapInput.HRVReading],
                         dayStart: Date, calendar: Calendar) -> Baseline {
        var hrvMedians: [Double] = []
        var asleepHours: [Double] = []
        for back in 1...baselineNights {
            guard let start = calendar.date(byAdding: .day, value: -back, to: dayStart),
                  let night = RecapEngine.night(from: sleep, heartRate: [], dayStart: start, calendar: calendar) else {
                continue
            }
            if let median = RecapEngine.hrvNight(readings: hrv, night: night) {
                hrvMedians.append(median)
            }
            if back <= 6 {
                asleepHours.append(Double(night.asleepMinutes) / 60)
            }
        }
        var result = Baseline(hrv: nil, sleepMeanHours: nil, nights: hrvMedians.count)
        if hrvMedians.count >= 3 {
            result.hrv = RecapEngine.median(hrvMedians)
        }
        if asleepHours.count >= 3 {
            result.sleepMeanHours = asleepHours.reduce(0, +) / Double(asleepHours.count)
        }
        return result
    }

    // MARK: Runs

    static func run(from c: SpikeCandidate) -> RecapInput.Run {
        let samples = c.samples.map {
            RecapInput.HeartRateSample(date: $0.date, bpm: $0.bpm, motion: RecapInput.Motion(rawValue: $0.motion.rawValue) ?? .notSet)
        }
        var stage: RecapInput.SleepStage? = nil
        if c.attribution == .inBed {
            stage = c.inBed == .awake ? .awake : .unspecified
        }
        return RecapInput.Run(
            id: c.id, start: c.start, end: c.end, peakAt: c.peakAt, peak: c.peakHR,
            samples: samples, stepsPadded: nil,
            motionActive: c.samples.contains { $0.motion == .active },
            recoveredAt: c.recovery.map { c.peakAt.addingTimeInterval($0) },
            stage: stage
        )
    }

    /// "988" in the US and Canada only (RECAP 6.9); nil elsewhere.
    static func crisisNumber(locale: Locale = .current) -> String? {
        let region = locale.region?.identifier ?? ""
        return region == "US" || region == "CA" ? "988" : nil
    }

    // MARK: Queries

    private func heartRateSamples(in window: DateInterval) async throws -> [RecapInput.HeartRateSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate(for: window))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await mapped { try await descriptor.result(for: self.store) }
        let readings = samples.map { sample -> RecapInput.HeartRateSample in
            RecapInput.HeartRateSample(
                date: sample.startDate,
                bpm: Int(sample.quantity.doubleValue(for: HealthService.bpm).rounded()),
                motion: HealthService.motion(of: sample)
            )
        }
        return HealthService.downsampled(readings)
    }

    private static func motion(of sample: HKQuantitySample) -> RecapInput.Motion {
        guard let raw = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber,
              let context = HKHeartRateMotionContext(rawValue: raw.intValue) else {
            return .notSet
        }
        switch context {
        case .sedentary: return .sedentary
        case .active: return .active
        case .notSet: return .notSet
        @unknown default: return .notSet
        }
    }

    /// One reading per minute, the median of the minute, dated at its first
    /// reading; an `active` context anywhere in the minute is kept. Sparse
    /// background data (5 min apart) passes through unchanged.
    static func downsampled(_ readings: [RecapInput.HeartRateSample]) -> [RecapInput.HeartRateSample] {
        guard readings.count > 1 else {
            return readings
        }
        var result: [RecapInput.HeartRateSample] = []
        var bucket: [RecapInput.HeartRateSample] = []
        var bucketIndex = Int.min
        func flush() {
            guard let first = bucket.first else { return }
            let sorted = bucket.map { $0.bpm }.sorted()
            let median = sorted[sorted.count / 2]
            let active = bucket.contains { $0.motion == .active }
            result.append(RecapInput.HeartRateSample(date: first.date, bpm: median, motion: active ? .active : first.motion))
            bucket = []
        }
        for r in readings {
            let index = Int(floor(r.date.timeIntervalSinceReferenceDate / downsampleSeconds))
            if index != bucketIndex {
                flush()
                bucketIndex = index
            }
            bucket.append(r)
        }
        flush()
        return result
    }

    /// Apple's daily resting values from the last week, oldest first.
    private func restingHistory(before date: Date) async throws -> [Int] {
        let week = DateInterval(start: date.addingTimeInterval(-7 * 86400), end: date)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate), predicate: predicate(for: week))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await mapped { try await descriptor.result(for: self.store) }
        return samples.suffix(7).map { Int($0.quantity.doubleValue(for: HealthService.bpm).rounded()) }
    }

    private func hrvReadings(in window: DateInterval) async throws -> [RecapInput.HRVReading] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRateVariabilitySDNN), predicate: predicate(for: window))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await mapped { try await descriptor.result(for: self.store) }
        return samples.map {
            RecapInput.HRVReading(date: $0.startDate, sdnn: $0.quantity.doubleValue(for: .secondUnit(with: .milli)))
        }
    }

    /// Per-minute sums rather than raw samples: the iPhone and the Watch
    /// both record steps for the same minutes, and the statistics query
    /// merges the sources the way the Health app does instead of doubling.
    private func stepSamples(in window: DateInterval) async throws -> [RecapInput.Steps] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate(for: window)),
            options: .cumulativeSum,
            anchorDate: window.start,
            intervalComponents: DateComponents(minute: 1)
        )
        let collection = try await mapped { try await descriptor.result(for: self.store) }
        return collection.statistics().compactMap { bucket -> RecapInput.Steps? in
            guard let sum = bucket.sumQuantity() else {
                return nil
            }
            return RecapInput.Steps(start: bucket.startDate, end: bucket.endDate, count: sum.doubleValue(for: .count()))
        }
    }

    private func workouts(in window: DateInterval) async throws -> [RecapInput.Workout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate(for: window))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await mapped { try await descriptor.result(for: self.store) }
        return workouts.map {
            RecapInput.Workout(start: $0.startDate, end: $0.endDate, kind: HealthService.name(of: $0.workoutActivityType))
        }
    }

    private static func name(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        default: return "workout"
        }
    }

    private func exerciseIntervals(in window: DateInterval) async throws -> [RecapInput.Interval] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.appleExerciseTime), predicate: predicate(for: window))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await mapped { try await descriptor.result(for: self.store) }
        return samples.map { RecapInput.Interval(start: $0.startDate, end: $0.endDate) }
    }

    private func sleepSamples(in window: DateInterval) async throws -> [RecapInput.SleepSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate(for: window))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await mapped { try await descriptor.result(for: self.store) }
        return samples.compactMap { sample -> RecapInput.SleepSample? in
            guard let stage = HealthService.stage(of: sample.value) else {
                return nil
            }
            return RecapInput.SleepSample(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    private static func stage(of value: Int) -> RecapInput.SleepStage? {
        guard let stage = HKCategoryValueSleepAnalysis(rawValue: value) else {
            return nil
        }
        switch stage {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        case .asleepUnspecified: return .unspecified
        @unknown default: return nil
        }
    }

    private func caffeine(in window: DateInterval) async throws -> [RecapInput.Caffeine] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryCaffeine), predicate: predicate(for: window))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await mapped { try await descriptor.result(for: self.store) }
        return samples.map {
            RecapInput.Caffeine(date: $0.startDate, mg: $0.quantity.doubleValue(for: HealthService.milligram))
        }
    }

    /// Active energy the Apple Watch recorded over `window`, in kcal. nil when
    /// there is none or it cannot be read. Only Watch samples count: an
    /// iPhone alone also writes a little active energy.
    private func watchActiveEnergy(in window: DateInterval) async -> Double? {
        guard window.duration > 0 else {
            return nil
        }
        let fromWatch = HKQuery.predicateForObjects(withDeviceProperty: HKDevicePropertyKeyModel, allowedValues: ["Watch"])
        let both = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate(for: window), fromWatch])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.activeEnergyBurned), predicate: both),
            options: .cumulativeSum
        )
        guard let statistics = try? await mapped({ try await descriptor.result(for: self.store) }),
              let sum = statistics.sumQuantity() else {
            return nil
        }
        let kcal = sum.doubleValue(for: .kilocalorie())
        return kcal > 0 ? kcal : nil
    }

    private func predicate(for window: DateInterval) -> NSPredicate {
        return HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])
    }

    /// Types added in an update may not have been asked for yet; until they
    /// are, the recap goes on without them instead of failing.
    private func unlessNotAsked<T>(_ work: () async throws -> [T]) async throws -> [T] {
        do {
            return try await work()
        } catch HealthServiceError.notAuthorized {
            return []
        }
    }

    private func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            let ns = error as NSError
            if ns.domain == HKErrorDomain {
                if ns.code == HKError.Code.errorDatabaseInaccessible.rawValue {
                    throw HealthServiceError.protectedDataUnavailable
                }
                if ns.code == HKError.Code.errorAuthorizationNotDetermined.rawValue {
                    throw HealthServiceError.notAuthorized
                }
            }
            throw error
        }
    }
}
