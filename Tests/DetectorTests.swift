import XCTest
import Foundation

// Background heart rate on a Watch is sparse, one reading every 3 to 10
// minutes, so every fixture here has only a handful of samples. Resting is 60
// unless a test says otherwise: elevated from 85 bpm (max(60 + 25, 80)),
// recovered at 70 (resting + 10). Nothing is ever filtered: every run of two
// or more elevated readings comes back, and the tests check what it is called.
final class DetectorTests: XCTestCase {

    private let base = Fx.date("2026-09-23 23:00")

    private func at(_ minutes: Double) -> Date {
        return base.addingTimeInterval(minutes * 60)
    }

    private func hr(_ pairs: [(Double, Int)]) -> [HRSample] {
        return pairs.map { HRSample(date: at($0.0), bpm: $0.1) }
    }

    private func span(_ from: Double, _ to: Double) -> DateInterval {
        return DateInterval(start: at(from), end: at(to))
    }

    private var window: DateInterval {
        return span(-18 * 60, 18 * 60)
    }

    // Romp's pre-v3 signature on purpose: it must keep compiling.
    private func detect(
        _ samples: [HRSample],
        steps: [StepSample] = [],
        workouts: [DateInterval] = [],
        exercise: [DateInterval] = [],
        asleep: [DateInterval] = [],
        sleepWindow: DateInterval? = nil,
        resting: Int? = 60,
        detector: Detector = Detector()
    ) -> [SpikeCandidate] {
        return detector.candidates(heartRate: samples, steps: steps, workouts: workouts,
                                   exerciseIntervals: exercise, asleepIntervals: asleep,
                                   sleepWindow: sleepWindow, restingHR: resting, window: window)
    }

    func testSparseRunOfFourIsAStillSpike() throws {
        let samples = hr([(-30, 62), (-8, 64), (10, 108), (14, 128), (19, 138), (24, 121), (31, 72), (40, 63)])
        let found = detect(samples, steps: [StepSample(start: at(0), end: at(30), count: 30)])
        XCTAssertEqual(found.count, 1)
        let c = try XCTUnwrap(found.first)
        XCTAssertEqual(c.start, at(10))
        XCTAssertEqual(c.end, at(24))
        XCTAssertEqual(c.peakHR, 138)
        XCTAssertEqual(c.peakAt, at(19))
        XCTAssertEqual(c.avgHR, 124)
        XCTAssertEqual(c.samples.count, 4)
        XCTAssertEqual(c.elevatedCount, 4)
        XCTAssertEqual(c.restingHR, 60)
        XCTAssertEqual(c.magnitude, 78)
        XCTAssertEqual(c.attribution, .still)
        XCTAssertNil(c.inBed)
        // 24 of the 30 steps fall in the padded 5..29 window: 10 per 10 min.
        XCTAssertEqual(c.stepDensity, 10, accuracy: 0.001)
        // Peak at 19, first reading at or under 70 is the 63 at 40.
        XCTAssertEqual(c.recovery ?? 0, 21 * 60, accuracy: 0.001)
        XCTAssertEqual(c.recoveryMinutes, 21)
        XCTAssertEqual(c.clarity, 1, accuracy: 0.0001)
    }

    // The 22-minute padded window makes 20 steps per 10 min exactly 44 steps.
    func testStepsDecideStillVersusMoving() {
        let samples = hr([(0, 110), (3, 120), (6, 125), (9, 122), (12, 105), (15, 72)])
        func steps(_ n: Double) -> [StepSample] {
            return [StepSample(start: at(0), end: at(12), count: n)]
        }
        let still = detect(samples, steps: steps(40))
        XCTAssertEqual(still.map { $0.attribution }, [Attribution.still])
        XCTAssertEqual(still.first?.stepDensity ?? 0, 40 / 2.2, accuracy: 0.001)

        let moving = detect(samples, steps: steps(44))
        XCTAssertEqual(moving.map { $0.attribution }, [Attribution.moving])
        XCTAssertEqual(moving.first?.stepDensity ?? 0, 20, accuracy: 0.001)

        XCTAssertEqual(detect(samples, steps: steps(900)).map { $0.attribution }, [Attribution.moving])
        XCTAssertEqual(detect(samples).map { $0.attribution }, [Attribution.still])
    }

    func testStepsStraddlingTheEdgeArePartlyCounted() {
        let steps = [StepSample(start: at(-10), end: at(10), count: 1000), StepSample(start: at(5), end: at(5), count: 7)]
        XCTAssertEqual(Detector.steps(steps, from: at(0), to: at(20)), 507, accuracy: 0.001)
        XCTAssertEqual(Detector.steps(steps, from: at(20), to: at(30)), 0)
    }

    func testActiveMotionContextMeansMoving() {
        let sedentary = [HRSample(date: at(0), bpm: 110, motion: .sedentary), HRSample(date: at(4), bpm: 120, motion: .sedentary)]
        XCTAssertEqual(detect(sedentary).map { $0.attribution }, [Attribution.still])

        let walking = [HRSample(date: at(0), bpm: 110, motion: .sedentary), HRSample(date: at(4), bpm: 120, motion: .active)]
        XCTAssertEqual(detect(walking).map { $0.attribution }, [Attribution.moving], "one active reading is enough")
    }

    func testExerciseMinutesMeanMoving() {
        let samples = hr([(0, 118), (4, 134), (8, 140), (12, 128)])
        XCTAssertEqual(detect(samples, exercise: [span(4, 5)]).map { $0.attribution }, [Attribution.moving])
        XCTAssertEqual(detect(samples, exercise: [span(12, 13)]).map { $0.attribution }, [Attribution.still],
                       "touching is not overlapping")
    }

    func testWorkoutIsOneBlockAndItsPaddingStripsBackground() throws {
        let samples = hr([(0, 130), (4, 145), (8, 150), (12, 140)])

        let covered = detect(samples, workouts: [span(-5, 40)])
        XCTAssertEqual(covered.map { $0.attribution }, [Attribution.workout])
        let block = try XCTUnwrap(covered.first)
        XCTAssertEqual(block.start, at(0))
        XCTAssertEqual(block.end, at(12))
        XCTAssertEqual(block.peakHR, 150)
        XCTAssertEqual(block.elevatedCount, 4)

        XCTAssertEqual(detect(samples).map { $0.attribution }, [Attribution.still])

        // A workout starting at 12 reaches back 10 minutes: the readings at
        // 4, 8 and 12 are its warm-up, the lone one at 0 is not a spike.
        let touching = detect(samples, workouts: [span(12, 40)])
        XCTAssertEqual(touching.map { $0.attribution }, [Attribution.workout])
        XCTAssertEqual(touching.first?.start, at(4))

        // Padding that reaches nothing leaves the spike alone.
        XCTAssertEqual(detect(samples, workouts: [span(25, 60)]).map { $0.attribution }, [Attribution.still])

        // Padding that swallows only the last reading: the still run shrinks
        // to 0..8 and the workout has one reading, too few for a block.
        let clipped = detect(samples, workouts: [span(22, 60)])
        XCTAssertEqual(clipped.map { $0.attribution }, [Attribution.still])
        XCTAssertEqual(clipped.first?.end, at(8))
    }

    func testWorkoutBlocksMergeWhenTheirPaddingOverlaps() throws {
        let samples = hr([(2, 120), (10, 130), (18, 125), (28, 135), (36, 128)])
        let found = detect(samples, workouts: [span(0, 20), span(25, 40)])
        XCTAssertEqual(found.count, 1, "two workouts five minutes apart are one block")
        let c = try XCTUnwrap(found.first)
        XCTAssertEqual(c.attribution, .workout)
        XCTAssertEqual(c.start, at(2))
        XCTAssertEqual(c.end, at(36))
        XCTAssertEqual(c.peakHR, 135)
        XCTAssertEqual(c.peakAt, at(28))
    }

    func testWorkoutBlockKeepsOneReadingPerMinute() throws {
        // 5-second workout data for 10 minutes, 121 readings from 100 to 106.
        let dense = (0..<121).map { HRSample(date: base.addingTimeInterval(Double($0) * 5), bpm: 100 + $0 % 7) }
        let found = detect(dense, workouts: [span(0, 10)])
        let c = try XCTUnwrap(found.first)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(c.attribution, .workout)
        XCTAssertEqual(c.elevatedCount, 121)
        XCTAssertEqual(c.samples.count, 11, "one per minute, 0 through 10")
        XCTAssertEqual(c.samples.map { $0.bpm }.max(), 106, "the peak is kept")
        XCTAssertEqual(c.peakHR, 106)
        XCTAssertEqual(c.avgHR, 103, "the average is from every reading")
    }

    func testLoneReadingIsNotASpike() {
        XCTAssertEqual(detect(hr([(-5, 70), (0, 135), (5, 72)])).count, 0)
    }

    func testRunsFiveMinutesApartMerge() throws {
        let samples = hr([(0, 110), (3, 125), (6, 118), (8, 75), (11, 130), (14, 142), (17, 120)])
        let found = detect(samples)
        XCTAssertEqual(found.count, 1)
        let c = try XCTUnwrap(found.first)
        XCTAssertEqual(c.start, at(0))
        XCTAssertEqual(c.end, at(17))
        XCTAssertEqual(c.samples.count, 7, "the low reading in the gap stays in the curve")
        XCTAssertEqual(c.elevatedCount, 6)
        XCTAssertEqual(c.peakHR, 142)
        XCTAssertNil(c.recovery, "nothing under 70 after the peak")
    }

    func testRunsOverSixMinutesApartStaySeparate() {
        let seven = detect(hr([(0, 110), (3, 120), (10, 125), (13, 130)]))
        XCTAssertEqual(seven.map { $0.start }, [at(0), at(10)])
        XCTAssertEqual(seven.map { $0.end }, [at(3), at(13)])

        XCTAssertEqual(detect(hr([(0, 110), (6, 120)])).count, 1, "six minutes is still one run")

        let ten = detect(hr([(0, 110), (3, 135), (6, 128), (9, 121), (14, 75),
                             (19, 130), (22, 142), (25, 138), (28, 120)]))
        XCTAssertEqual(ten.map { $0.start }, [at(0), at(19)])
        XCTAssertEqual(ten.map { $0.end }, [at(9), at(28)])
    }

    func testNoDurationFloorOrCeilingAndNoPeakBar() {
        XCTAssertEqual(detect(hr([(0, 120), (3, 130)])).first?.duration, 3 * 60, "3 minutes")
        XCTAssertEqual(detect(hr([(0, 120), (0.5, 130)])).first?.duration, 30, "two readings in one minute")

        let marathon = (0...25).map { (Double($0) * 5, 120) }
        let long = detect(hr(marathon))
        XCTAssertEqual(long.count, 1, "125 minutes is one long stretch")
        XCTAssertEqual(long.first?.duration, 125 * 60)

        let mild = detect(hr([(0, 95), (4, 99), (8, 98), (12, 97)]))
        XCTAssertEqual(mild.count, 1, "resting + 25 is the only bar")
        XCTAssertEqual(mild.first?.magnitude, 39)

        XCTAssertEqual(detect(hr([(0, 130), (10, 140)])).count, 0, "ten minutes apart is two lone readings")
    }

    func testThresholdIsRestingPlusTwentyFiveWithAFloorOfEighty() {
        let low = hr([(0, 86), (4, 88), (8, 89)])
        XCTAssertEqual(detect(low, resting: 60).count, 1)
        XCTAssertEqual(detect(low, resting: nil).count, 0, "unknown resting is 65, so 90")
        XCTAssertEqual(detect(hr([(0, 100), (4, 110)]), resting: nil).first?.restingHR, 65)
        XCTAssertEqual(detect(hr([(0, 100), (4, 110)]), resting: 300).first?.restingHR, 65, "an impossible resting is unknown")

        XCTAssertEqual(detect(hr([(0, 78), (4, 79)]), resting: 40).count, 0, "the floor is 80")
        let floored = detect(hr([(0, 80), (4, 82)]), resting: 40)
        XCTAssertEqual(floored.count, 1)
        XCTAssertEqual(floored.first?.magnitude, 42)

        XCTAssertEqual(detect(hr([(0, 95), (4, 96)]), resting: 72).count, 0, "elevated starts at 97")
        XCTAssertEqual(detect(hr([(0, 97), (4, 98)]), resting: 72).count, 1)

        var wide = Detector()
        wide.elevatedMargin = 30
        XCTAssertEqual(detect(hr([(0, 86), (4, 88), (8, 89)]), detector: wide).count, 0, "Wide setting: 90")
    }

    func testSamplesOutsideTheWindowAreIgnored() {
        let far = hr([(-30 * 60, 120), (-30 * 60 + 5, 130), (-30 * 60 + 10, 125), (-30 * 60 + 15, 128)])
        XCTAssertEqual(detect(far).count, 0)
    }

    func testRecoveryIsMeasuredFromThePeakToRestingPlusTen() throws {
        let samples = hr([(0, 100), (5, 120), (10, 110), (15, 80), (20, 68)])
        let c = try XCTUnwrap(detect(samples).first)
        XCTAssertEqual(c.peakAt, at(5))
        XCTAssertEqual(c.end, at(10), "80 is under the threshold, so the run ends at 10")
        XCTAssertEqual(c.recovery ?? 0, 15 * 60, accuracy: 0.001)
        XCTAssertEqual(c.recoveryMinutes, 15)

        let exact = try XCTUnwrap(detect(hr([(0, 100), (5, 120), (10, 110), (15, 70)])).first)
        XCTAssertEqual(exact.recoveryMinutes, 10, "at the target counts")

        // Resting 55: the run now includes the 80, and 68 is over 65.
        let lower = try XCTUnwrap(detect(samples, resting: 55).first)
        XCTAssertEqual(lower.end, at(15))
        XCTAssertNil(lower.recovery)
    }

    func testRecoveryGivesUpAfterAnHourOrAtTheNextSpike() throws {
        XCTAssertNil(try XCTUnwrap(detect(hr([(0, 100), (5, 120), (10, 110), (70, 68)])).first).recovery,
                     "65 minutes after the peak is too late")
        XCTAssertEqual(try XCTUnwrap(detect(hr([(0, 100), (5, 120), (10, 110), (64, 68)])).first).recoveryMinutes, 59)

        let two = detect(hr([(0, 100), (5, 120), (10, 110), (30, 120), (34, 125), (40, 68)]))
        XCTAssertEqual(two.count, 2)
        XCTAssertNil(two[0].recovery, "the next spike came first")
        XCTAssertEqual(two[1].recoveryMinutes, 6)
    }

    func testInBedSpikesAreSubtypedAwakeOrAsleep() throws {
        // Asleep 0..180 and 200..480, awake for twenty minutes in between.
        let asleep = [span(0, 180), span(200, 480)]
        func rise(_ start: Double) -> [HRSample] {
            return hr([(start, 100), (start + 4, 111), (start + 8, 100)])
        }
        func kind(_ start: Double) throws -> (Attribution, InBedKind?) {
            let c = try XCTUnwrap(detect(rise(start), asleep: asleep).first)
            return (c.attribution, c.inBed)
        }

        XCTAssertEqual(try kind(100).0, .inBed)
        XCTAssertEqual(try kind(100).1, .asleep)
        XCTAssertEqual(try kind(186).1, .awake, "peak in the awake gap")
        XCTAssertEqual(try kind(174).1, .awake, "peak within five minutes of the gap")
        XCTAssertEqual(try kind(160).1, .asleep, "peak well inside an asleep stretch")

        let after = try kind(485)
        XCTAssertEqual(after.0, .still, "the window ended at 480")
        XCTAssertNil(after.1)

        let straddling = try kind(476)
        XCTAssertEqual(straddling.0, .inBed, "in bed is decided by the start")
        XCTAssertEqual(straddling.1, .asleep, "the check is clipped to the window")
    }

    func testSleepWindowCanBeWiderThanTheAsleepIntervals() throws {
        let rise = hr([(-20, 100), (-16, 110), (-12, 100)])
        let asleep = [span(0, 480)]
        XCTAssertEqual(detect(rise, asleep: asleep).first?.attribution, .still, "before the first asleep reading")

        let c = try XCTUnwrap(detect(rise, asleep: asleep, sleepWindow: span(-30, 480)).first)
        XCTAssertEqual(c.attribution, .inBed)
        XCTAssertEqual(c.inBed, .awake, "in bed, not yet asleep")
    }

    func testCandidatesAreOrderedByStartAcrossBuckets() {
        let samples = hr([(-95, 130), (-90, 140), (0, 100), (4, 110), (250, 100), (254, 110)])
        let found = detect(samples, workouts: [span(-100, -80)], asleep: [span(200, 400)])
        XCTAssertEqual(found.map { $0.attribution }, [Attribution.workout, .still, .inBed])
        XCTAssertEqual(found.map { $0.start }, [at(-95), at(0), at(250)])
    }

    func testClarity() throws {
        XCTAssertEqual(Detector.clarity(peak: 85, resting: 60, still: true, elevatedCount: 2), 0.3, accuracy: 0.0001,
                       "only just elevated, still, two readings")
        XCTAssertEqual(Detector.clarity(peak: 110, resting: 60, still: true, elevatedCount: 3), 1, accuracy: 0.0001)
        XCTAssertEqual(Detector.clarity(peak: 97, resting: 60, still: false, elevatedCount: 3), 0.44, accuracy: 0.0001)
        XCTAssertEqual(Detector.clarity(peak: 200, resting: 60, still: false, elevatedCount: 2), 0.5, accuracy: 0.0001)

        let clear = try XCTUnwrap(detect(hr([(0, 120), (5, 135), (10, 130)])).first)
        XCTAssertEqual(clear.clarity, 1, accuracy: 0.0001)
        let faint = try XCTUnwrap(detect(hr([(0, 88), (4, 90)])).first)
        XCTAssertEqual(faint.clarity, 0.4, accuracy: 0.0001)
    }

    func testCandidateBecomesAMoment() throws {
        let c = try XCTUnwrap(detect(hr([(10, 108), (14, 128), (19, 138), (24, 121), (32, 70)])).first)
        XCTAssertEqual(c.id, "\(Int(at(10).timeIntervalSince1970))-\(Int(at(24).timeIntervalSince1970))")

        let m = try c.makeMoment(noticed: true, tag: .meeting)
        XCTAssertEqual(m.start, at(10))
        XCTAssertEqual(m.duration, 14 * 60)
        XCTAssertEqual(m.kind, .spike)
        XCTAssertEqual(m.attribution, .still)
        XCTAssertNil(m.inBed)
        XCTAssertEqual(m.source, .health)
        XCTAssertEqual(m.visibility, .private)
        XCTAssertEqual(m.restingHR, 60)
        XCTAssertEqual(m.heartRate.map { $0.offset }, [0, 240, 540, 840])
        XCTAssertEqual(m.avgHR, 124)
        XCTAssertEqual(m.peakHR, 138)
        XCTAssertEqual(m.magnitude, 78)
        XCTAssertEqual(m.recoverySeconds, 13 * 60)
        XCTAssertEqual(m.noticed, true)
        XCTAssertEqual(m.tag, .meeting)
        XCTAssertEqual(m.note, "")
        XCTAssertNil(m.title)
        XCTAssertNil(m.calendarLabel)
        XCTAssertNil(m.recap)
        XCTAssertNil(m.night)

        let unanswered = try c.makeMoment()
        XCTAssertNil(unanswered.noticed)
        XCTAssertNil(unanswered.tag)

        let other = try c.makeMoment(attributionOverride: .other)
        XCTAssertEqual(other.attribution, .other, "Something else keeps the spike, drops it from the still count")
    }

    func testInBedCandidateKeepsItsSubtypeInTheMoment() throws {
        let c = try XCTUnwrap(detect(hr([(100, 100), (104, 110)]), asleep: [span(0, 480)]).first)
        var m = try c.makeMoment()
        XCTAssertEqual(m.attribution, .inBed)
        XCTAssertEqual(m.inBed, .asleep)
        m.attribution = .other
        XCTAssertNil(m.inBed, "the sub-type goes with the attribution")
    }
}

// Romp's realistic day, with the verdicts turned around: the same readings
// that its detector threw out as noise are what Frayed is about. Nothing is
// rejected; each stretch is found and named. Resting 60.
final class DetectorNoiseTests: XCTestCase {

    private let base = Fx.date("2026-09-23 23:00")

    private func at(_ minutes: Double) -> Date {
        return base.addingTimeInterval(minutes * 60)
    }

    private func hr(_ pairs: [(Double, Int)]) -> [HRSample] {
        return pairs.map { HRSample(date: at($0.0), bpm: $0.1) }
    }

    private func span(_ from: Double, _ to: Double) -> DateInterval {
        return DateInterval(start: at(from), end: at(to))
    }

    private var window: DateInterval {
        return span(-18 * 60, 18 * 60)
    }

    private func detect(
        _ samples: [HRSample],
        steps: [StepSample] = [],
        workouts: [DateInterval] = [],
        exercise: [DateInterval] = [],
        asleep: [DateInterval] = []
    ) -> [SpikeCandidate] {
        return Detector().candidates(heartRate: samples, steps: steps, workouts: workouts,
                                     exerciseIntervals: exercise, asleepIntervals: asleep,
                                     restingHR: 60, window: window)
    }

    // 14:00, a stressful call at the desk. 3 elevated readings, 8 min,
    // peak 103, back under 70 eighteen minutes after the peak.
    private let deskSpike: [(Double, Int)] = [(-545, 70), (-540, 92), (-536, 103), (-532, 96), (-525, 74), (-518, 68)]

    // 17:30, driving in traffic: long and mild, peak 98. Traffic counts.
    private let driving: [(Double, Int)] = [(-330, 91), (-324, 96), (-318, 98), (-312, 94), (-306, 97), (-300, 93)]

    // 12:10, stairs and a fast walk. 5 readings, 12 min, peak 131, 420 steps.
    private let stairs: [(Double, Int)] = [(-650, 112), (-647, 128), (-644, 131), (-641, 126), (-638, 118)]
    private var stairsSteps: [StepSample] {
        return [StepSample(start: at(-650), end: at(-638), count: 420)]
    }

    // 19:00, a logged gym workout. 5 readings, 16 min, peak 156.
    private let workout: [(Double, Int)] = [(-240, 125), (-236, 148), (-232, 156), (-228, 150), (-224, 138)]
    private var workoutInterval: DateInterval {
        return span(-245, -220)
    }

    // 08:30, a bike commute with no workout started: Apple still counts
    // exercise minutes. 4 readings, 12 min, peak 140.
    private let commute: [(Double, Int)] = [(-870, 118), (-866, 134), (-862, 140), (-858, 128)]
    private var commuteExercise: [DateInterval] {
        return (0..<6).map { span(-866 + Double($0), -865 + Double($0)) }
    }

    // 03:10, a heart-rate rise during sleep (a dream, a hot room).
    // 4 readings, 12 min, peak 126.
    private let sleepRise: [(Double, Int)] = [(250, 100), (254, 118), (258, 126), (262, 112)]
    private var asleep: [DateInterval] {
        return [span(45, 420)]
    }

    // 23:10, what Romp called the real thing: 4 readings, 14 min, peak 138,
    // still. Here it is one more still spike.
    private let lateSpike: [(Double, Int)] = [(-5, 64), (10, 108), (14, 128), (19, 138), (24, 121), (32, 70)]

    func testDeskSpikeIsFoundAndStill() throws {
        let found = detect(hr(deskSpike))
        XCTAssertEqual(found.count, 1)
        let c = try XCTUnwrap(found.first)
        XCTAssertEqual(c.attribution, .still)
        XCTAssertEqual(c.start, at(-540))
        XCTAssertEqual(c.end, at(-532))
        XCTAssertEqual(c.peakHR, 103)
        XCTAssertEqual(c.magnitude, 43)
        XCTAssertEqual(c.elevatedCount, 3)
        XCTAssertEqual(c.recoveryMinutes, 18)
    }

    func testDrivingIsFoundAndStill() throws {
        let c = try XCTUnwrap(detect(hr(driving)).first)
        XCTAssertEqual(c.attribution, .still)
        XCTAssertEqual(c.elevatedCount, 6)
        XCTAssertEqual(c.duration, 30 * 60)
        XCTAssertEqual(c.peakHR, 98)
        XCTAssertNil(c.recovery, "never got under 70 while the readings lasted")
    }

    func testStairsAreMoving() throws {
        let c = try XCTUnwrap(detect(hr(stairs), steps: stairsSteps).first)
        XCTAssertEqual(c.attribution, .moving)
        XCTAssertEqual(c.stepDensity, 420 / 2.2, accuracy: 0.01)
        XCTAssertEqual(detect(hr(stairs)).first?.attribution, .still, "without the step count it reads as still")
    }

    func testTheGymIsAWorkoutBlock() throws {
        let c = try XCTUnwrap(detect(hr(workout), workouts: [workoutInterval]).first)
        XCTAssertEqual(c.attribution, .workout)
        XCTAssertEqual(c.start, at(-240))
        XCTAssertEqual(c.end, at(-224))
        XCTAssertEqual(c.peakHR, 156)
        XCTAssertEqual(detect(hr(workout)).first?.attribution, .still, "with no workout logged it is a still spike")
    }

    func testTheCommuteIsMovingThroughExerciseMinutes() throws {
        let c = try XCTUnwrap(detect(hr(commute), exercise: commuteExercise).first)
        XCTAssertEqual(c.attribution, .moving)
        XCTAssertEqual(detect(hr(commute)).first?.attribution, .still)
    }

    func testTheNightRiseIsInBedAndAsleep() throws {
        let c = try XCTUnwrap(detect(hr(sleepRise), asleep: asleep).first)
        XCTAssertEqual(c.attribution, .inBed)
        XCTAssertEqual(c.inBed, .asleep)
        XCTAssertEqual(c.peakHR, 126)
        XCTAssertEqual(detect(hr(sleepRise)).first?.attribution, .still, "awake it would be a still spike")
    }

    func testTheLateSpikeIsJustAnotherStillSpike() throws {
        let c = try XCTUnwrap(detect(hr(lateSpike)).first)
        XCTAssertEqual(c.attribution, .still)
        XCTAssertEqual(c.start, at(10))
        XCTAssertEqual(c.end, at(24))
        XCTAssertEqual(c.recoveryMinutes, 13)
    }

    func testWholeDayIsClassified() {
        let all = deskSpike + driving + stairs + workout + commute + sleepRise + lateSpike
        let found = detect(hr(all), steps: stairsSteps, workouts: [workoutInterval],
                           exercise: commuteExercise, asleep: asleep)
        XCTAssertEqual(found.count, 7, "nothing is thrown away")
        XCTAssertEqual(found.map { $0.attribution },
                       [Attribution.moving, .moving, .still, .still, .workout, .still, .inBed],
                       "ordered by start: commute, stairs, desk, traffic, gym, late spike, night rise")

        var histogram: [Attribution: Int] = [:]
        for c in found {
            histogram[c.attribution, default: 0] += 1
        }
        let expected: [Attribution: Int] = [.still: 3, .moving: 2, .workout: 1, .inBed: 1]
        XCTAssertEqual(histogram, expected)

        XCTAssertEqual(found.filter { $0.attribution.isStill }.map { $0.recoveryMinutes }, [18, nil, 13])
        XCTAssertEqual(found.filter { $0.attribution.isDaytime }.count, 6, "the headline count leaves the night out")
    }

    func testASpikeThatEndsAsSleepBeginsIsDaytime() throws {
        let c = try XCTUnwrap(detect(hr(lateSpike), asleep: [span(24, 480)]).first)
        XCTAssertEqual(c.attribution, .still, "in bed is decided by where the spike starts")
    }
}
