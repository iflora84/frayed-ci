import XCTest
import Foundation

// Every date here is local wall-clock time in America/Los_Angeles and every
// calculation goes through an explicit Calendar, so the CI runner's zone,
// locale and clock never matter. 2026-09-24 is a Thursday; weeks start on
// Monday unless a test says otherwise. Fx is shared with MomentTests,
// MomentStoreTests and DetectorTests.
enum Fx {
    static let zone: TimeZone = TimeZone(identifier: "America/Los_Angeles")!

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

    static func moment(_ start: String, minutes: Double = 30, id: UUID = UUID()) -> Moment {
        let s = date(start)
        return try! Moment(id: id, start: s, end: s.addingTimeInterval(minutes * 60))
    }

    static func tempFileURL() -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("frayed-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("moments.json", isDirectory: false)
    }
}

final class HeartRateTests: XCTestCase {

    private func points(_ bpms: [Int], step: Int = 300) -> [HRPoint] {
        return bpms.enumerated().map { HRPoint(offset: $0.offset * step, bpm: $0.element) }
    }

    func testNormalizedSortsClipsAndKeepsTheEndReading() {
        let raw = [
            HRPoint(offset: 600, bpm: 120), HRPoint(offset: 0, bpm: 100), HRPoint(offset: 601, bpm: 110),
            HRPoint(offset: -1, bpm: 100), HRPoint(offset: 300, bpm: 20), HRPoint(offset: 300, bpm: 241)
        ]
        XCTAssertEqual(HRPoint.normalized(raw, duration: 600), [HRPoint(offset: 0, bpm: 100), HRPoint(offset: 600, bpm: 120)],
                       "the last elevated sample is the moment's end, so offset == duration stays")
        XCTAssertNil(HRPoint.mean([]))
        XCTAssertEqual(HRPoint.mean(points([100, 110, 125])), 112)
    }

    func testRisePeakRecovery() {
        let segments = SpikeSegment.split(points([90, 110, 150, 155, 120, 95]), duration: 1800)
        XCTAssertEqual(segments.map { $0.phase }, [.rise, .peak, .recovery])
        XCTAssertEqual(segments.map { $0.start }, [0, 600, 1200])
        XCTAssertEqual(segments.map { $0.end }, [600, 1200, 1800])
        XCTAssertEqual(segments.map { $0.avgHR }, [100, 153, 108])
    }

    func testNoSegmentsForFlatOrSingleReading() {
        XCTAssertEqual(SpikeSegment.split(points([120]), duration: 600), [])
        XCTAssertEqual(SpikeSegment.split(points([120, 120]), duration: 600), [])
    }

    func testPeakAtTheStartLeavesAnEmptyRise() {
        let segments = SpikeSegment.split(points([150, 100]), duration: 600)
        XCTAssertEqual(segments[0].duration, 0)
        XCTAssertNil(segments[0].avgHR)
        XCTAssertEqual(segments[1].avgHR, 150)
        XCTAssertEqual(segments[2].avgHR, 100)
    }

    func testRecoveryTimeToRestingPlusTen() {
        // The peak phase ends with the 155 at 900 s; the 95 at 1500 s is the
        // first reading at or under 85 + 10.
        XCTAssertEqual(SpikeSegment.recoveryTime(points: points([90, 110, 150, 155, 120, 95]), restingHR: 85), 600)
        // No resting rate: 65 stands in, so the target is 75. The 74 also
        // lowers the halfway threshold to 114.5, so the 120 at 1200 s is still
        // peak phase and the come-down is measured from there: 300 s.
        XCTAssertEqual(SpikeSegment.recoveryTime(points: points([90, 110, 150, 155, 120, 74]), restingHR: nil), 300)
        XCTAssertEqual(SpikeSegment.recoveryTime(points: points([90, 110, 150, 155, 120, 74]), restingHR: 300), 300,
                       "an out-of-range resting rate falls back too")
    }

    func testNeverSettlesReturnsNil() {
        XCTAssertNil(SpikeSegment.recoveryTime(points: points([90, 110, 150, 155, 120, 95]), restingHR: 60))
        XCTAssertNil(SpikeSegment.recoveryTime(points: points([90, 110, 150, 155]), restingHR: 60), "readings end at the peak")
        XCTAssertNil(SpikeSegment.recoveryTime(points: points([120, 120]), restingHR: 60), "a flat curve has no peak")
        XCTAssertNil(SpikeSegment.recoveryTime(points: [], restingHR: 60))
    }
}

final class AgePolicyTests: XCTestCase {

    private func oldEnough(born: String, on now: String) -> Bool {
        return AgePolicy.isAdult(birthDate: Fx.date(born), now: Fx.date(now), calendar: Fx.calendar())
    }

    func testMinimumAgeIsSixteen() {
        XCTAssertEqual(AgePolicy.minimumAge, 16)
    }

    func testSixteenthBirthdayCountsWhateverTheTime() {
        XCTAssertTrue(oldEnough(born: "2010-09-24 23:59", on: "2026-09-24 00:01"))
        XCTAssertTrue(oldEnough(born: "2010-09-24 00:00", on: "2026-09-24 12:00"))
    }

    func testOneDayShortIsNotEnough() {
        XCTAssertFalse(oldEnough(born: "2010-09-25 00:00", on: "2026-09-24 23:59"))
        XCTAssertFalse(oldEnough(born: "2010-12-31 12:00", on: "2026-09-24 12:00"))
    }

    func testOlderAndYoungerYears() {
        XCTAssertTrue(oldEnough(born: "1990-12-31 12:00", on: "2026-01-01 12:00"))
        XCTAssertFalse(oldEnough(born: "2015-01-01 12:00", on: "2026-09-24 12:00"))
    }

    func testLeapDayBirthday() {
        // Sixteen years after a leap day is a leap year again, so the exact
        // birthday exists; the day before it is still short.
        XCTAssertFalse(oldEnough(born: "2008-02-29 12:00", on: "2024-02-28 23:59"))
        XCTAssertTrue(oldEnough(born: "2008-02-29 12:00", on: "2024-02-29 00:01"))
        // A year on the age is past 16, so Feb 28 of a non-leap year counts.
        XCTAssertTrue(oldEnough(born: "2008-02-29 12:00", on: "2025-02-28 12:00"))
    }
}
