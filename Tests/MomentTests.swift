import XCTest
import Foundation

// The model's own rules: validation, the lenient decoder, and the fields
// that only exist on one kind or attribution. Every date is LA wall-clock
// through Fx (FrayedCoreTests.swift).
final class MomentTests: XCTestCase {

    private let start = Fx.date("2026-09-24 12:00")

    private func moment(
        minutes: Double = 30,
        kind: MomentKind = .spike,
        attribution: Attribution = .still,
        inBed: InBedKind? = nil,
        heartRate: [HRPoint] = [],
        recap: Moment.RecapSummary? = nil,
        night: Moment.NightSummary? = nil
    ) throws -> Moment {
        return try Moment(
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            kind: kind,
            attribution: attribution,
            inBed: inBed,
            heartRate: heartRate,
            recap: recap,
            night: night
        )
    }

    private func decode(_ json: String) throws -> Moment {
        return try FileMomentStore.decoder().decode([Moment].self, from: Data(json.utf8))[0]
    }

    private static let sampleRecap = Moment.RecapSummary(
        spikeCount: 6, stillCount: 4, movingCount: 1, workoutCount: 1, noticedCount: 2,
        load: 44, recoverySeconds: 990, calmestBpm: 58, dayType: "meetingSurvivor",
        coverage: 0.92, hourlyPeaks: [0, 0, 0, 0, 71, 108, 90, 96, 99, 82, 112, 90, 84, 92, 171, 80]
    )

    private static let sampleNight = Moment.NightSummary(
        asleepMinutes: 425, awakeMinutes: 25, awakenings: 2, lowestHR: 51, sleepScore: 78,
        awakeRises: 1, asleepRises: 1, hrvNight: 44, hrvBaseline: 46
    )

    func testEndMustBeAfterStart() {
        XCTAssertThrowsError(try Moment(start: start, end: start)) { error in
            XCTAssertEqual(error as? MomentValidationError, .endNotAfterStart)
        }
        XCTAssertThrowsError(try Moment(start: start, end: start.addingTimeInterval(-60))) { error in
            XCTAssertEqual(error as? MomentValidationError, .endNotAfterStart)
        }
    }

    func testDurationCappedAtTwentyFourHours() throws {
        let day = try moment(minutes: 24 * 60, kind: .recap)
        XCTAssertEqual(day.duration, 24 * 3600, "a recap spans a day")
        XCTAssertThrowsError(try moment(minutes: 24 * 60 + 1)) { error in
            XCTAssertEqual(error as? MomentValidationError, .longerThanMaximum)
        }
    }

    func testDatesAreWholeSeconds() throws {
        let m = try Moment(start: start.addingTimeInterval(0.7), end: start.addingTimeInterval(600.2))
        XCTAssertEqual(m.start, start)
        XCTAssertEqual(m.end, start.addingTimeInterval(600))
    }

    func testHeartRateOutsideRangeBecomesNil() throws {
        let end = start.addingTimeInterval(600)
        let low = try Moment(start: start, end: end, avgHR: 29, peakHR: 241, restingHR: 500)
        XCTAssertNil(low.avgHR)
        XCTAssertNil(low.peakHR)
        XCTAssertNil(low.restingHR)
        XCTAssertNil(low.magnitude)
        let edges = try Moment(start: start, end: end, avgHR: 30, peakHR: 240, restingHR: 62)
        XCTAssertEqual(edges.avgHR, 30)
        XCTAssertEqual(edges.peakHR, 240)
        XCTAssertEqual(edges.magnitude, 178)
    }

    func testNegativeRecoveryBecomesNil() throws {
        let end = start.addingTimeInterval(600)
        XCTAssertNil(try Moment(start: start, end: end, recoverySeconds: -5).recoverySeconds)
        XCTAssertEqual(try Moment(start: start, end: end, recoverySeconds: 0).recoverySeconds, 0)
        XCTAssertEqual(try Moment(start: start, end: end, recoverySeconds: 540).recoverySeconds, 540)
    }

    func testHeartRateIsSortedClippedAndFillsAverages() throws {
        let m = try moment(minutes: 10, heartRate: [
            HRPoint(offset: 300, bpm: 140),
            HRPoint(offset: 0, bpm: 100),
            HRPoint(offset: 900, bpm: 150),
            HRPoint(offset: 120, bpm: 20)
        ])
        XCTAssertEqual(m.heartRate, [HRPoint(offset: 0, bpm: 100), HRPoint(offset: 300, bpm: 140)])
        XCTAssertEqual(m.avgHR, 120)
        XCTAssertEqual(m.peakHR, 140)
    }

    func testTitleIsTrimmedAndBlankBecomesNil() throws {
        var m = try moment()
        XCTAssertNil(m.title)
        m.title = "  Stand-up  "
        XCTAssertEqual(m.title, "Stand-up")
        m.title = "   "
        XCTAssertNil(m.title)
        XCTAssertNil(try Moment(start: start, end: start.addingTimeInterval(60), title: "\n").title)
    }

    func testInBedKindOnlyLivesOnAnInBedSpike() throws {
        XCTAssertNil(try moment(attribution: .still, inBed: .awake).inBed)

        var m = try moment(attribution: .inBed, inBed: .awake)
        XCTAssertEqual(m.inBed, .awake)
        m.attribution = .still
        XCTAssertNil(m.inBed, "the sub-type goes with the attribution")
        m.inBed = .asleep
        XCTAssertNil(m.inBed, "and cannot come back without it")
        m.attribution = .inBed
        m.inBed = .asleep
        XCTAssertEqual(m.inBed, .asleep)
    }

    func testRecapAndNightFollowTheKind() throws {
        let spike = try moment(kind: .spike, recap: MomentTests.sampleRecap, night: MomentTests.sampleNight)
        XCTAssertNil(spike.recap)
        XCTAssertNil(spike.night)

        let rough = try moment(kind: .roughNight, recap: MomentTests.sampleRecap, night: MomentTests.sampleNight)
        XCTAssertNil(rough.recap)
        XCTAssertEqual(rough.night, MomentTests.sampleNight)

        var recap = try moment(kind: .recap, recap: MomentTests.sampleRecap, night: MomentTests.sampleNight)
        XCTAssertEqual(recap.recap, MomentTests.sampleRecap)
        XCTAssertEqual(recap.night, MomentTests.sampleNight)
        recap.night = nil
        XCTAssertNil(recap.night, "a recap may have no night")

        var edited = spike
        edited.recap = MomentTests.sampleRecap
        edited.night = MomentTests.sampleNight
        XCTAssertNil(edited.recap)
        XCTAssertNil(edited.night)
    }

    func testRecordWithOnlyIdStartAndEndDecodesWithDefaults() throws {
        let id = UUID()
        let m = try decode("""
        [{"id":"\(id.uuidString)","start":"2026-09-24T19:00:00Z","end":"2026-09-24T19:30:00Z"}]
        """)
        XCTAssertEqual(m.id, id)
        XCTAssertEqual(m.start, start)
        XCTAssertEqual(m.duration, 1800)
        XCTAssertEqual(m.kind, .spike)
        XCTAssertEqual(m.attribution, .still)
        XCTAssertNil(m.inBed)
        XCTAssertNil(m.avgHR)
        XCTAssertNil(m.peakHR)
        XCTAssertNil(m.restingHR)
        XCTAssertEqual(m.heartRate, [])
        XCTAssertNil(m.recoverySeconds)
        XCTAssertNil(m.noticed)
        XCTAssertNil(m.tag)
        XCTAssertEqual(m.note, "")
        XCTAssertNil(m.title)
        XCTAssertEqual(m.source, .manual)
        XCTAssertEqual(m.visibility, .private)
        XCTAssertNil(m.calendarLabel)
        XCTAssertNil(m.recap)
        XCTAssertNil(m.night)
    }

    func testUnknownValuesFallBackFieldByField() throws {
        let m = try decode("""
        [{"id":"\(UUID().uuidString)","start":"2026-09-24T19:00:00Z","end":"2026-09-24T19:30:00Z",\
        "kind":"solo","attribution":"walking","inBed":"dreaming","tag":"spicy","source":"watch",\
        "visibility":"public","heartRate":"oops","restingHR":900,"title":"   ","noticed":"yes",\
        "recoverySeconds":"soon","calendarLabel":7,"recap":"nope","night":[]}]
        """)
        XCTAssertEqual(m.kind, .spike)
        XCTAssertEqual(m.attribution, .still)
        XCTAssertNil(m.inBed)
        XCTAssertNil(m.tag)
        XCTAssertEqual(m.source, .manual)
        XCTAssertEqual(m.visibility, .private)
        XCTAssertEqual(m.heartRate, [])
        XCTAssertNil(m.restingHR)
        XCTAssertNil(m.title)
        XCTAssertNil(m.noticed)
        XCTAssertNil(m.recoverySeconds)
        XCTAssertNil(m.calendarLabel)
        XCTAssertNil(m.recap)
        XCTAssertNil(m.night)
    }

    func testNestedSummariesAreLenientToo() throws {
        let m = try decode("""
        [{"id":"\(UUID().uuidString)","start":"2026-09-24T04:00:00Z","end":"2026-09-24T20:00:00Z",\
        "kind":"recap","recap":{"stillCount":4,"load":"heavy","dayType":"","hourlyPeaks":[70,999,"x"]},\
        "night":{"asleepMinutes":"x","awakenings":3,"sleepScore":140,"newField":true}}]
        """)
        let recap = try XCTUnwrap(m.recap)
        XCTAssertEqual(recap.stillCount, 4)
        XCTAssertEqual(recap.spikeCount, 0)
        XCTAssertNil(recap.load)
        XCTAssertNil(recap.dayType)
        XCTAssertEqual(recap.hourlyPeaks, [], "a strip that does not parse is dropped whole")

        let night = try XCTUnwrap(m.night)
        XCTAssertEqual(night.asleepMinutes, 0)
        XCTAssertEqual(night.awakenings, 3)
        XCTAssertEqual(night.sleepScore, 100)
        XCTAssertNil(night.lowestHR)
    }

    func testAnInvalidRecordThrowsSoTheStoreCanSkipIt() {
        XCTAssertThrowsError(try decode("""
        [{"id":"\(UUID().uuidString)","start":"2026-09-24T19:30:00Z","end":"2026-09-24T19:00:00Z"}]
        """))
        XCTAssertThrowsError(try decode("""
        [{"start":"2026-09-24T19:00:00Z","end":"2026-09-24T19:30:00Z"}]
        """), "id is required")
    }

    func testEveryFieldSurvivesTheJSONRoundTrip() throws {
        let label = CalendarLabel(eventID: "evt-1", title: "Q3 planning", people: 5,
                                  eventStart: Fx.date("2026-09-24 09:00"), eventEnd: Fx.date("2026-09-24 10:00"))
        let spike = try Moment(
            start: Fx.date("2026-09-24 09:05"),
            end: Fx.date("2026-09-24 09:30"),
            kind: .spike,
            attribution: .still,
            avgHR: 98,
            peakHR: 108,
            restingHR: 62,
            heartRate: [HRPoint(offset: 0, bpm: 92), HRPoint(offset: 600, bpm: 108), HRPoint(offset: 1500, bpm: 90)],
            recoverySeconds: 1200,
            noticed: true,
            tag: .panic,
            note: "stays local",
            title: "That call",
            source: .health,
            visibility: .friends,
            calendarLabel: label
        )
        let night = try Moment(
            start: Fx.date("2026-09-23 23:20"),
            end: Fx.date("2026-09-24 06:50"),
            kind: .roughNight,
            attribution: .inBed,
            inBed: .awake,
            source: .health,
            visibility: .anonymous,
            night: MomentTests.sampleNight
        )
        let recap = try Moment(
            start: Fx.date("2026-09-24 04:00"),
            end: Fx.date("2026-09-24 20:02"),
            kind: .recap,
            attribution: .other,
            restingHR: 62,
            noticed: false,
            source: .health,
            recap: MomentTests.sampleRecap,
            night: MomentTests.sampleNight
        )
        for original in [spike, night, recap] {
            let data = try FileMomentStore.encoder().encode([original])
            let reloaded = try FileMomentStore.decoder().decode([Moment].self, from: data)
            XCTAssertEqual(reloaded, [original])
        }

        let data = try FileMomentStore.encoder().encode([spike])
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(raw.contains("\"tag\":\"panic\""), raw)
        XCTAssertTrue(raw.contains("\"title\":\"Q3 planning\""), "the label is kept on the device")
        XCTAssertFalse(raw.contains("duration"))
        XCTAssertFalse(raw.contains("magnitude"))
    }

    func testCalendarLabelIsCleaned() {
        let blank = CalendarLabel(title: "   ", people: -3)
        XCTAssertNil(blank.title)
        XCTAssertEqual(blank.people, 0)
        let solo = CalendarLabel(title: " Focus time ")
        XCTAssertEqual(solo.title, "Focus time")
        XCTAssertEqual(solo.people, 0)
    }

    func testSummariesClampTheirNumbers() {
        let hot = Moment.RecapSummary(spikeCount: -1, load: 140, recoverySeconds: -9, calmestBpm: 20,
                                      dayType: " ", coverage: 1.5, hourlyPeaks: Array(repeating: 300, count: 30))
        XCTAssertEqual(hot.spikeCount, 0)
        XCTAssertEqual(hot.load, 100)
        XCTAssertNil(hot.recoverySeconds)
        XCTAssertNil(hot.calmestBpm)
        XCTAssertNil(hot.dayType)
        XCTAssertEqual(hot.coverage, 1)
        XCTAssertEqual(hot.hourlyPeaks.count, 24)
        XCTAssertEqual(hot.hourlyPeaks.first, 0, "an impossible reading reads as no reading")
        XCTAssertEqual(Moment.RecapSummary(load: -5).load, 0)
        XCTAssertNil(Moment.RecapSummary().load)

        let night = Moment.NightSummary(asleepMinutes: -10, lowestHR: 20, sleepScore: 120, hrvNight: -1, hrvBaseline: 0)
        XCTAssertEqual(night.asleepMinutes, 0)
        XCTAssertEqual(night.sleepScore, 100)
        XCTAssertNil(night.lowestHR)
        XCTAssertNil(night.hrvNight)
        XCTAssertNil(night.hrvBaseline)
        XCTAssertEqual(Moment.NightSummary(sleepScore: -3).sleepScore, 0)
    }

    func testNewestFirstBreaksTiesById() throws {
        let a = try Moment(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, start: start, end: start.addingTimeInterval(60))
        let b = try Moment(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, start: start, end: start.addingTimeInterval(60))
        let later = try Moment(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(3660))
        XCTAssertEqual(Moment.newestFirst([b, later, a]).map { $0.id }, [later.id, a.id, b.id])
    }

    func testAttributionRoles() {
        XCTAssertEqual(Attribution.allCases.filter { $0.isStill }, [.still])
        XCTAssertEqual(Attribution.allCases.filter { $0.isDaytime }, [.workout, .moving, .still])
        XCTAssertFalse(Attribution.inBed.isDaytime)
        XCTAssertFalse(Attribution.other.isDaytime, "Something else leaves the headline count")
    }

    func testTagOrderAndLabelsAreTheUsersWords() {
        XCTAssertEqual(SpikeTag.allCases, [.meeting, .argument, .deadline, .panic, .excited, .somethingGood, .caffeine, .noIdea])
        XCTAssertEqual(SpikeTag.panic.label, "Panic", "repeated verbatim, never expanded")
        XCTAssertEqual(SpikeTag.somethingGood.label, "Something good")
        XCTAssertEqual(SpikeTag.noIdea.label, "No idea")
    }

    // RECAP 0.1: the model's own strings describe what the body did and
    // never name a condition. The user's tag words are theirs and are
    // checked separately above.
    func testModelLabelsAvoidTheBannedWords() {
        let banned = ["panic attack", "anxiety", "depress", "burnout", "burned out", "disorder",
                      "symptom", "diagnos", "stressed out", "unhealthy", "episode"]
        var labels = MomentKind.allCases.map { $0.label }
        labels += Attribution.allCases.map { $0.label }
        labels += Attribution.allCases.map { $0.phrase }
        labels += SpikeTag.allCases.map { $0.label }
        for label in labels {
            for word in banned {
                XCTAssertFalse(label.lowercased().contains(word), "\(label) contains \(word)")
            }
        }
    }
}
