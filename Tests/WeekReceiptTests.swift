import XCTest
import Foundation

// Seven synthetic days run through RecapEngine.generate, the way the golden
// tests build theirs, then summed into a receipt. Times are local
// wall-clock in America/Los_Angeles through Fx.calendar().
final class WeekReceiptTests: XCTestCase {

    private let calendar = Fx.calendar()

    /// One fixture day keyed "yyyy-MM-dd"; "HH:mm" resolves on that day.
    private struct Day {
        let key: String

        func at(_ hhmm: String, _ dayOffset: Int = 0) -> Date {
            let d = Fx.date("\(key) \(hhmm)")
            return Fx.calendar().date(byAdding: .day, value: dayOffset, to: d)!
        }

        func input(coverage: Double = 0.9, awake: Double = 13) -> RecapInput {
            return RecapInput(
                dayKey: key, dayStart: at("04:00"), now: at("20:00"), recapTime: at("20:00"),
                userId: "receipt", restingHistory: [60], coverage: coverage, awakeTrackedHours: awake
            )
        }

        func still(_ id: String, _ peakAt: String, peak: Int, recovery: Int?) -> RecapInput.Run {
            let peakDate = at(peakAt)
            return RecapInput.Run(
                id: id, start: peakDate.addingTimeInterval(-3 * 60), end: peakDate.addingTimeInterval(8 * 60),
                peakAt: peakDate, peak: peak, stepsPadded: 4,
                recoveredAt: recovery.map { peakDate.addingTimeInterval(TimeInterval($0 * 60)) }
            )
        }

        func night(asleep: Int) -> RecapInput.Night {
            return RecapInput.Night(start: at("23:30", -1), end: at("06:30"), asleepMinutes: asleep,
                                    awakeMinutes: 20, awakenings: 2, lowHR: 50)
        }
    }

    private func recap(_ input: RecapInput) -> DayRecap {
        return RecapEngine.generate(input, calendar: calendar)
    }

    /// Mon 21: three still spikes, all recovered (8, 10, 12 -> median 10).
    /// Tue 22: two still, one never seen settling (6, nil -> median 6).
    /// Wed 23: Watch off. Thu 24: no recap at all. Fri 25: nothing still.
    /// Sat and Sun are after `now`.
    private func week(tuesdayRecovers: Bool = false) -> [DayRecap] {
        let mon = Day(key: "2026-09-21")
        var monInput = mon.input()
        monInput.night = mon.night(asleep: 420)
        monInput.runs = [
            mon.still("a", "09:00", peak: 95, recovery: 8),
            mon.still("b", "13:00", peak: 101, recovery: 10),
            mon.still("c", "16:00", peak: 97, recovery: 12)
        ]
        monInput.calmest = DayRecap.Calmest(at: mon.at("11:00"), bpm: 58)

        let tue = Day(key: "2026-09-22")
        var tueInput = tue.input()
        tueInput.night = tue.night(asleep: 400)
        tueInput.runs = [
            tue.still("a", "10:00", peak: 99, recovery: 6),
            tue.still("b", "15:00", peak: 104, recovery: tuesdayRecovers ? 7 : nil)
        ]
        tueInput.calmest = DayRecap.Calmest(at: tue.at("12:00"), bpm: 55)

        let wed = Day(key: "2026-09-23")
        let wedInput = wed.input(coverage: 0, awake: 0)

        let fri = Day(key: "2026-09-25")
        var friInput = fri.input()
        friInput.night = fri.night(asleep: 440)
        friInput.calmest = DayRecap.Calmest(at: fri.at("14:00"), bpm: 57)

        return [recap(friInput), recap(wedInput), recap(tueInput), recap(monInput)]
    }

    private func build(_ recaps: [DayRecap], count: Int = 6) -> WeekReceipt {
        let week = calendar.dateInterval(of: .weekOfYear, for: Fx.date("2026-09-23 12:00"))!
        return WeekReceipt.build(week: week, recaps: recaps, receiptCount: count, calendar: calendar,
                                 now: Fx.date("2026-09-25 20:30"))
    }

    func testFixtureDaysClassifyAsExpected() {
        let recaps = week()
        let byKey = Dictionary(uniqueKeysWithValues: recaps.map { ($0.dayKey, $0) })
        XCTAssertEqual(byKey["2026-09-21"]?.counts.still, 3)
        XCTAssertEqual(byKey["2026-09-21"]?.recovery?.median, 10)
        XCTAssertEqual(byKey["2026-09-21"]?.type, .justAWeekday)
        XCTAssertEqual(byKey["2026-09-22"]?.recovery?.median, 6)
        XCTAssertEqual(byKey["2026-09-22"]?.recovery?.knownCount, 1)
        XCTAssertEqual(byKey["2026-09-23"]?.isNotWorn, true)
        XCTAssertEqual(byKey["2026-09-25"]?.counts.still, 0)
    }

    func testSevenLinesMondayFirst() {
        let receipt = build(week())
        XCTAssertEqual(receipt.lines.count, 7)
        XCTAssertEqual(receipt.lines.map { $0.weekday }, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(receipt.lines[0].day, Fx.date("2026-09-21 00:00"))
        XCTAssertEqual(receipt.weekNumber, 39)
        XCTAssertEqual(receipt.rangeLabel, "Sep 21 – 27")
    }

    func testTypeLabels() {
        let lines = build(week()).lines
        XCTAssertEqual(lines[0].typeLabel, "Just a Monday")
        XCTAssertEqual(lines[0].dayType, .justAWeekday)
        XCTAssertEqual(lines[2].typeLabel, "Watch off")
        XCTAssertFalse(lines[2].worn)
        XCTAssertEqual(lines[3].typeLabel, "Watch off")
        XCTAssertNil(lines[3].dayType)
        XCTAssertEqual(lines[5].typeLabel, "Not yet")
        XCTAssertEqual(lines[6].typeLabel, "Not yet")
        XCTAssertFalse(lines[6].worn)
    }

    func testStillSpikesAndAverages() {
        let receipt = build(week())
        XCTAssertEqual(receipt.stillSpikes, 5)
        XCTAssertEqual(receipt.lines.map { $0.stillSpikes }, [3, 2, 0, 0, 0, 0, 0])
        XCTAssertEqual(receipt.cameDownAverageMinutes, 8)
        XCTAssertEqual(receipt.wornDays, 3)
        XCTAssertEqual(receipt.asleepAverageMinutes, 420)
        XCTAssertEqual(receipt.barcodeWidths, [5, 4, 2, 2, 2, 2, 2])
    }

    func testEveryOneCameDownNeedsEveryRecoveryKnown() {
        XCTAssertFalse(build(week()).everyOneCameDown)
        XCTAssertTrue(build(week(tuesdayRecovers: true)).everyOneCameDown)
    }

    func testFastestAndCalmest() {
        let receipt = build(week())
        XCTAssertEqual(receipt.fastest?.weekday, "Tue")
        XCTAssertEqual(receipt.fastest?.recoveryMinutes, 6)
        XCTAssertEqual(receipt.calmest?.bpm, 55)
        XCTAssertEqual(receipt.calmest?.line.weekday, "Tue")
        XCTAssertEqual(receipt.calmest?.at, Fx.date("2026-09-22 12:00"))
    }

    func testReceiptNumberFormat() {
        XCTAssertEqual(build(week(), count: 6).receiptNumber, "2026 W39 0006")
        XCTAssertEqual(build(week(), count: 118).receiptNumber, "2026 W39 0118")
    }

    func testEmptyWeekIsAllWatchOffOrNotYet() {
        let receipt = build([])
        XCTAssertEqual(receipt.stillSpikes, 0)
        XCTAssertFalse(receipt.everyOneCameDown)
        XCTAssertNil(receipt.cameDownAverageMinutes)
        XCTAssertNil(receipt.fastest)
        XCTAssertNil(receipt.calmest)
        XCTAssertEqual(receipt.lines.map { $0.typeLabel },
                       ["Watch off", "Watch off", "Watch off", "Watch off", "Watch off", "Not yet", "Not yet"])
    }

    func testLabelsPassTheBannedWordSweep() {
        for line in build(week()).lines {
            XCTAssertNil(RecapCopy.bannedWord(in: line.typeLabel), line.typeLabel)
        }
    }
}
