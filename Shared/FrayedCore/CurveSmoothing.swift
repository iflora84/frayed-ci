import Foundation

/// Light smoothing for dense heart-rate curves, so a Watch recording reads
/// like a smooth line rather than beat-to-beat jitter. Sparse background
/// readings are left exactly as they are.
enum CurveSmoothing {
    static let window = 5
    static let minimumCount = 12
    /// Readings at most this many seconds apart (median) count as dense.
    static let denseSpacing: Double = 60

    static func isDense(times: [Double]) -> Bool {
        guard times.count >= minimumCount else {
            return false
        }
        var gaps: [Double] = []
        for index in 1..<times.count {
            gaps.append(times[index] - times[index - 1])
        }
        let sorted = gaps.sorted()
        return sorted[sorted.count / 2] <= denseSpacing
    }

    /// A centred moving average over `window` readings, narrowing at the
    /// ends. The first, last and highest readings keep their raw values, so
    /// the curve still starts, ends and peaks where the numbers say.
    static func movingAverage(_ values: [Double], window: Int = CurveSmoothing.window) -> [Double] {
        guard values.count > 2, window > 1 else {
            return values
        }
        let reach = window / 2
        var result = values
        for index in 1..<(values.count - 1) {
            let from = max(0, index - reach)
            let to = min(values.count - 1, index + reach)
            var total = 0.0
            for other in from...to {
                total += values[other]
            }
            result[index] = total / Double(to - from + 1)
        }
        if let top = values.indices.max(by: { values[$0] < values[$1] }) {
            result[top] = values[top]
        }
        return result
    }

    /// Smoothed values when the series is dense, the input otherwise.
    static func smooth(times: [Double], values: [Double]) -> [Double] {
        guard times.count == values.count, isDense(times: times) else {
            return values
        }
        return movingAverage(values)
    }
}
