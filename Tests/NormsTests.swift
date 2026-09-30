import XCTest
import Foundation

final class NormsTests: XCTestCase {

    // RECAP 0.1 and PORT's never-say list. "anxious" and "panic" are checked
    // too: the only "Panic" in the app is a tag the user picks.
    private let banned = ["panic", "anxiety", "anxious", "depress", "burnout", "burned out", "disorder",
                          "symptom", "diagnos", "episode", "stressed out", "unhealthy", "!"]

    private func assertClean(_ string: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(string.isEmpty, label, file: file, line: line)
        for word in banned {
            XCTAssertFalse(string.lowercased().contains(word), "\(label) contains \"\(word)\": \(string)", file: file, line: line)
        }
    }

    // MARK: Facts

    func testEveryFactIsShortSourcedAndLinked() {
        XCTAssertGreaterThanOrEqual(Facts.all.count, 30)
        for fact in Facts.all {
            XCTAssertLessThanOrEqual(fact.text.count, 160, fact.id)
            XCTAssertFalse(fact.text.isEmpty, fact.id)
            XCTAssertFalse(fact.citation.isEmpty, fact.id)
            XCTAssertTrue(fact.url.hasPrefix("https://"), fact.id)
            XCTAssertNotNil(URL(string: fact.url), fact.id)
        }
        XCTAssertEqual(Set(Facts.all.map { $0.id }).count, Facts.all.count, "ids are unique")
        XCTAssertEqual(Set(Facts.all.map { $0.text }).count, Facts.all.count, "texts are unique")
    }

    func testFactsNeverNameACondition() {
        for fact in Facts.all {
            assertClean(fact.text, fact.id)
            assertClean(fact.citation, fact.id)
        }
    }

    func testAudienceDeckIncludesTheGeneralFacts() {
        XCTAssertEqual(Facts.for(audience: .all).count, Facts.all.count)
        let hrv = Facts.for(audience: .hrv)
        XCTAssertTrue(hrv.allSatisfy { $0.audience == .hrv || $0.audience == .all })
        XCTAssertTrue(hrv.contains { $0.audience == .hrv })
        XCTAssertTrue(hrv.contains { $0.audience == .all })
        XCTAssertFalse(hrv.contains { $0.audience == .sleep })
        for audience in Fact.Audience.allCases {
            XCTAssertTrue(Facts.for(audience: audience).contains { $0.audience == audience }, audience.rawValue)
        }
        XCTAssertEqual(hrv.map { $0.id }, Facts.all.filter { $0.audience == .hrv || $0.audience == .all }.map { $0.id }, "deck order is the source order")
    }

    // MARK: Age bands

    func testAgeBands() {
        XCTAssertEqual(AgeBand(age: 15), .from16to24, "under-16 cannot pass the gate but lands somewhere")
        XCTAssertEqual(AgeBand(age: 16), .from16to24)
        XCTAssertEqual(AgeBand(age: 24), .from16to24)
        XCTAssertEqual(AgeBand(age: 25), .from25to34)
        XCTAssertEqual(AgeBand(age: 34), .from25to34)
        XCTAssertEqual(AgeBand(age: 35), .from35to44)
        XCTAssertEqual(AgeBand(age: 44), .from35to44)
        XCTAssertEqual(AgeBand(age: 45), .from45to54)
        XCTAssertEqual(AgeBand(age: 54), .from45to54)
        XCTAssertEqual(AgeBand(age: 55), .from55to64)
        XCTAssertEqual(AgeBand(age: 64), .from55to64)
        XCTAssertEqual(AgeBand(age: 65), .from65)
        XCTAssertEqual(AgeBand(age: 90), .from65)
        XCTAssertEqual(AgeBand.from16to24.label, "16-24")
        XCTAssertEqual(AgeBand.from65.label, "65+")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        XCTAssertEqual(AgeBand(birthYear: 2001, now: now, calendar: calendar), .from25to34)
        XCTAssertEqual(AgeBand(birthYear: 2002, now: now, calendar: calendar), .from16to24)
        XCTAssertEqual(AgeBand(birthYear: 1961, now: now, calendar: calendar), .from65)
    }

    func testSexLabels() {
        XCTAssertEqual(SexCategory.allCases.map { $0.label }, ["Female", "Male", "Non-binary", "Prefer not to say"])
    }

    // MARK: Reference bands

    func testRestingHeartRateBandsFollowQuer() {
        let male = Norms.baseline(for: .from35to44, sex: .male).restingHR
        XCTAssertEqual(male.statistic, .central95)
        XCTAssertEqual(male.range?.lowerBound ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(male.range?.upperBound ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(male.rangeLabel, "50\u{2013}80")
        XCTAssertEqual(male.sources, [.quer2020])

        let female = Norms.baseline(for: .from65, sex: .female).restingHR
        XCTAssertEqual(female.range?.lowerBound ?? 0, 53, accuracy: 0.001)
        XCTAssertEqual(female.range?.upperBound ?? 0, 82, accuracy: 0.001)

        let undisclosed = Norms.baseline(for: .from16to24, sex: .undisclosed).restingHR
        XCTAssertEqual(undisclosed.range?.lowerBound ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(undisclosed.range?.upperBound ?? 0, 82, accuracy: 0.001)
        XCTAssertEqual(Norms.baseline(for: .from16to24, sex: .nonBinary).restingHR, undisclosed)

        for band in AgeBand.allCases {
            XCTAssertEqual(Norms.baseline(for: band, sex: .male).restingHR, male, "the paper gives no per-age band")
        }
    }

    func testSDNNBandsFollowVossAndNunan() {
        let men = Norms.baseline(for: .from35to44, sex: .male).sdnn
        XCTAssertEqual(men.statistic, .meanSD)
        XCTAssertEqual(men.range?.lowerBound ?? 0, 44.6 - 16.8, accuracy: 0.001)
        XCTAssertEqual(men.range?.upperBound ?? 0, 44.6 + 16.8, accuracy: 0.001)
        XCTAssertEqual(men.sources, [.voss2015])
        XCTAssertTrue(men.summary.contains("45 ms"), men.summary)
        XCTAssertTrue(men.summary.contains("35-44"), men.summary)

        let women = Norms.baseline(for: .from35to44, sex: .female).sdnn
        XCTAssertEqual(women.range?.lowerBound ?? 0, 45.4 - 20.5, accuracy: 0.001)
        XCTAssertEqual(women.range?.upperBound ?? 0, 45.4 + 20.5, accuracy: 0.001)

        let combined = Norms.baseline(for: .from35to44, sex: .undisclosed).sdnn
        XCTAssertEqual(combined.range?.lowerBound ?? 0, 45.4 - 20.5, accuracy: 0.001, "the wider of the two bands")
        XCTAssertEqual(combined.range?.upperBound ?? 0, 45.4 + 20.5, accuracy: 0.001)
        XCTAssertTrue(combined.basis.contains("combined"), combined.basis)

        let oldest = Norms.baseline(for: .from65, sex: .male).sdnn
        XCTAssertEqual(oldest.range?.lowerBound ?? 0, 29.6 - 13.2, accuracy: 0.001)
        XCTAssertTrue(oldest.summary.contains("65-74"), "the study stops at 74")

        let youngest = Norms.baseline(for: .from16to24, sex: .female).sdnn
        XCTAssertEqual(youngest.range?.lowerBound ?? 0, 34, accuracy: 0.001)
        XCTAssertEqual(youngest.range?.upperBound ?? 0, 66, accuracy: 0.001)
        XCTAssertEqual(youngest.sources, [.nunan2010], "nothing verified splits under-25s out")
        XCTAssertEqual(Norms.baseline(for: .from16to24, sex: .male).sdnn, youngest)

        for band in AgeBand.allCases where band != .from16to24 {
            let f = Norms.baseline(for: band, sex: .female).sdnn.range
            let m = Norms.baseline(for: band, sex: .male).sdnn.range
            XCTAssertNotEqual(f, m, band.label)
        }
    }

    func testEveryBaselineIsCompleteAndClean() {
        for band in AgeBand.allCases {
            for sex in SexCategory.allCases {
                let personal = Norms.baseline(for: band, sex: sex)
                XCTAssertEqual(personal.band, band)
                XCTAssertEqual(personal.sex, sex)
                for norm in [personal.restingHR, personal.sdnn] {
                    let label = "\(band.label) \(sex.rawValue)"
                    XCTAssertNotNil(norm.range, label)
                    if let range = norm.range {
                        XCTAssertLessThan(range.lowerBound, range.upperBound, label)
                    }
                    XCTAssertNotNil(norm.rangeLabel, label)
                    XCTAssertLessThanOrEqual(norm.summary.count, 160, label)
                    XCTAssertFalse(norm.sources.isEmpty, label)
                    assertClean(norm.summary, label)
                    assertClean(norm.basis, label)
                }
            }
        }
    }

    func testFindingsAndSourcesAreCleanAndLinked() {
        let findings = [Norms.compareToYourself, Norms.shortSDNN, Norms.restingSwing, Norms.settling, Norms.sleepFloor]
        for finding in findings {
            XCTAssertLessThanOrEqual(finding.text.count, 160, finding.text)
            assertClean(finding.text, finding.source.rawValue)
        }
        for source in Norms.Source.allCases {
            XCTAssertFalse(source.citation.isEmpty, source.rawValue)
            assertClean(source.citation, source.rawValue)
            XCTAssertTrue(source.url.hasPrefix("https://"), source.rawValue)
            XCTAssertNotNil(URL(string: source.url), source.rawValue)
        }
        XCTAssertEqual(Set(Norms.Source.allCases.map { $0.url }).count, Norms.Source.allCases.count, "one link per source")
    }

    func testThresholdsMatchTheScienceNotes() {
        XCTAssertEqual(Norms.Thresholds.sleepTarget.range.lowerBound, 7)
        XCTAssertEqual(Norms.Thresholds.sleepTarget.range.upperBound, 9)
        XCTAssertEqual(Norms.Thresholds.heartRateSettles.range.upperBound, 10)
        XCTAssertTrue(Norms.Thresholds.heartRateSettles.isSingle)
        XCTAssertFalse(Norms.Thresholds.labStressRise.isSingle)
        XCTAssertEqual(Norms.Thresholds.labStressRise.range.lowerBound, 9)
        XCTAssertEqual(Norms.Thresholds.labStressRise.range.upperBound, 13)
        XCTAssertEqual(Norms.Thresholds.unusualRestingSwing.range.lowerBound, 10)
        XCTAssertEqual(Norms.Thresholds.caffeineCutoff.range.lowerBound, 8.8, accuracy: 0.0001)
        XCTAssertEqual(Norms.Thresholds.breathingPace.range.lowerBound, 4.5, accuracy: 0.0001)
        XCTAssertEqual(Norms.Thresholds.breathingPace.range.upperBound, 6.5, accuracy: 0.0001)
        XCTAssertEqual(Norms.Thresholds.breathworkEffect.range.lowerBound, -0.35, accuracy: 0.0001)
        XCTAssertEqual(Norms.Thresholds.all.count, 13)
        for threshold in Norms.Thresholds.all {
            XCTAssertFalse(threshold.sources.isEmpty, threshold.name)
            XCTAssertFalse(threshold.unit.isEmpty, threshold.name)
            assertClean(threshold.name, threshold.name)
        }
        XCTAssertEqual(Set(Norms.Thresholds.all.map { $0.name }).count, Norms.Thresholds.all.count)
    }
}
