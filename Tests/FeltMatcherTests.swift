import XCTest
import Foundation

final class FeltMatcherTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ minutes: Double) -> Date {
        return t0.addingTimeInterval(minutes * 60)
    }

    private func spike(_ id: String, start: Double, peak: Double, end: Double, settled: Double?,
                       bucket: DayRecap.Bucket = .still) -> DayRecap.Spike {
        return DayRecap.Spike(
            id: id, start: at(start), end: at(end), peakAt: at(peak), peak: 100, resting: 60,
            magnitude: 40, elevatedMinutes: Int(end - start), stepDensity: 0, bucket: bucket,
            inBedKind: nil, recoveredAt: settled.map { at($0) }, recoveryMinutes: settled.map { Int($0 - peak) },
            label: nil, tag: nil
        )
    }

    func testStampInsideTheWidenedSpikeIsBackedByTheNearestPeak() {
        let spikes = [
            spike("a", start: 0, peak: 3, end: 8, settled: 12),
            spike("b", start: 20, peak: 22, end: 26, settled: 30, bucket: .moving)
        ]
        XCTAssertEqual(FeltMatcher.match(at(-9), spikes: spikes, beats: []), .backed(spikeId: "a", bucket: .still))
        XCTAssertEqual(FeltMatcher.match(at(21), spikes: spikes, beats: []), .backed(spikeId: "b", bucket: .moving))
        // 16 min sits in both widened windows; b's peak (6 min away) is nearer than a's (13).
        XCTAssertEqual(FeltMatcher.match(at(16), spikes: spikes, beats: []), .backed(spikeId: "b", bucket: .moving))
    }

    func testNoSpikeIsQuietWithReadingsAndBlindWithout() {
        let spikes = [spike("a", start: 0, peak: 3, end: 8, settled: 12)]
        let beats = [DayRecap.Beat(at: at(60), bpm: 64)]
        XCTAssertEqual(FeltMatcher.match(at(55), spikes: spikes, beats: beats), .quiet)
        XCTAssertEqual(FeltMatcher.match(at(90), spikes: spikes, beats: beats), .blind)
    }

    func testLines() {
        XCTAssertNil(FeltMatcher.line(FeltMatcher.Summary()))
        XCTAssertEqual(FeltMatcher.line(FeltMatcher.Summary(called: 1, backed: 1)),
                       "You called one today. The Watch backed you.")
        XCTAssertEqual(FeltMatcher.line(FeltMatcher.Summary(called: 3, backed: 2, blind: 1)),
                       "You called 3 today. The Watch backed you on 2. It just didn't see the rest.")
        XCTAssertEqual(FeltMatcher.line(FeltMatcher.Summary(called: 2, backed: 2)),
                       "You called 2 today. The Watch backed you on every one.")
        let all = [FeltMatcher.Summary(called: 1, quiet: 1), FeltMatcher.Summary(called: 1, blind: 1),
                   FeltMatcher.Summary(called: 4, backed: 1, quiet: 2, blind: 1)].compactMap { FeltMatcher.line($0) }
        for line in all {
            XCTAssertFalse(line.localizedCaseInsensitiveContains("missed"))
            XCTAssertFalse(line.localizedCaseInsensitiveContains("false alarm"))
            XCTAssertNil(RecapCopy.bannedWord(in: line))
        }
    }
}
