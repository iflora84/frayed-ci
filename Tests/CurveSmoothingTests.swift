import XCTest
import Foundation

final class CurveSmoothingTests: XCTestCase {

    func testMovingAverageFlattensJitterButKeepsEndsAndPeak() {
        let values: [Double] = [100, 110, 100, 110, 100, 150, 100, 110, 100, 110, 104]
        let smoothed = CurveSmoothing.movingAverage(values)
        XCTAssertEqual(smoothed.count, values.count)
        XCTAssertEqual(smoothed.first, 100)
        XCTAssertEqual(smoothed.last, 104)
        XCTAssertEqual(smoothed[5], 150, "the peak keeps its raw value")
        XCTAssertEqual(smoothed.max(), 150)
        XCTAssertEqual(smoothed[2], 104, accuracy: 0.001)
        XCTAssertEqual(smoothed[3], 114, accuracy: 0.001)
        XCTAssertEqual(smoothed[1], (100 + 110 + 100 + 110) / 4, accuracy: 0.001)
    }

    func testTinyInputsAreUntouched() {
        XCTAssertEqual(CurveSmoothing.movingAverage([]), [])
        XCTAssertEqual(CurveSmoothing.movingAverage([120]), [120])
        XCTAssertEqual(CurveSmoothing.movingAverage([120, 140]), [120, 140])
        XCTAssertEqual(CurveSmoothing.movingAverage([120, 90, 140], window: 1), [120, 90, 140])
    }

    func testOnlyDenseSeriesAreSmoothed() {
        let values = (0..<30).map { Double($0 % 2 == 0 ? 100 : 120) }
        let dense = (0..<30).map { Double($0 * 10) }
        let sparse = (0..<30).map { Double($0 * 240) }
        XCTAssertTrue(CurveSmoothing.isDense(times: dense))
        XCTAssertFalse(CurveSmoothing.isDense(times: sparse))
        XCTAssertFalse(CurveSmoothing.isDense(times: Array(dense.prefix(5))))
        XCTAssertEqual(CurveSmoothing.smooth(times: sparse, values: values), values)
        XCTAssertNotEqual(CurveSmoothing.smooth(times: dense, values: values), values)
        XCTAssertEqual(CurveSmoothing.smooth(times: Array(dense.prefix(3)), values: values), values, "mismatched lengths")
    }
}
