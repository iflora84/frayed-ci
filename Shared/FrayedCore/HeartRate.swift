import Foundation

/// One heart-rate reading, `offset` whole seconds after the moment start.
struct HRPoint: Codable, Hashable, Sendable {
    let offset: Int
    let bpm: Int

    init(offset: Int, bpm: Int) {
        self.offset = offset
        self.bpm = bpm
    }

    /// Sorted by offset, with readings outside the moment or outside the
    /// valid bpm range dropped. A reading at exactly `duration` stays: the
    /// last elevated sample is the moment's end.
    static func normalized(_ points: [HRPoint], duration: TimeInterval) -> [HRPoint] {
        return points
            .filter { $0.offset >= 0 && Double($0.offset) <= duration && Moment.heartRateRange.contains($0.bpm) }
            .sorted { ($0.offset, $0.bpm) < ($1.offset, $1.bpm) }
    }

    static func mean(_ points: [HRPoint]) -> Int? {
        guard !points.isEmpty else {
            return nil
        }
        let total = points.reduce(0) { $0 + $1.bpm }
        return Int((Double(total) / Double(points.count)).rounded())
    }

    /// Background readings are minutes apart, so each one stands for the
    /// time until the next: the first also covers the stretch from 0, the
    /// last one runs to `duration`. Expects normalized points.
    static func spans(_ points: [HRPoint], duration: TimeInterval) -> [HRSpan] {
        var result: [HRSpan] = []
        for (index, point) in points.enumerated() {
            let from = index == 0 ? 0 : Double(point.offset)
            let to = index + 1 < points.count ? Double(points[index + 1].offset) : max(duration, from)
            result.append(HRSpan(bpm: point.bpm, from: from, to: to))
        }
        return result
    }

    /// Time-weighted mean over `from..<to`, nil when no reading covers it.
    static func average(_ spans: [HRSpan], from: TimeInterval, to: TimeInterval) -> Int? {
        var weighted = 0.0
        var covered = 0.0
        for span in spans {
            let overlap = min(span.to, to) - max(span.from, from)
            if overlap > 0 {
                weighted += Double(span.bpm) * overlap
                covered += overlap
            }
        }
        guard covered > 0 else {
            return nil
        }
        return Int((weighted / covered).rounded())
    }
}

struct HRSpan: Equatable, Sendable {
    let bpm: Int
    let from: TimeInterval
    let to: TimeInterval
}

/// The three stretches of a spike, for the phase bar on the moment page.
enum SpikePhase: String, CaseIterable, Sendable {
    case rise, peak, recovery

    var label: String {
        switch self {
        case .rise: return "Rise"
        case .peak: return "Peak"
        case .recovery: return "Recovery"
        }
    }
}

struct SpikeSegment: Equatable, Sendable {
    /// Recovered means at or under resting + this (RECAP 4.3), the same
    /// target the recap engine uses.
    static let recoveryMargin = RecapEngine.recoveryMargin

    let phase: SpikePhase
    let start: TimeInterval
    let end: TimeInterval
    let avgHR: Int?

    var duration: TimeInterval {
        return end - start
    }

    /// Peak is the stretch from the first to the last reading at or above
    /// halfway between the lowest and highest reading; the rise comes before
    /// it and the recovery after. A phase can be empty (zero length, no
    /// avgHR). No segments with fewer than two readings or a flat curve.
    static func split(_ points: [HRPoint], duration: TimeInterval) -> [SpikeSegment] {
        guard let threshold = peakThreshold(points) else {
            return []
        }
        let spans = HRPoint.spans(points, duration: duration)
        guard let first = spans.firstIndex(where: { Double($0.bpm) >= threshold }),
              let last = spans.lastIndex(where: { Double($0.bpm) >= threshold }) else {
            return []
        }
        let peakStart = spans[first].from
        let peakEnd = spans[last].to
        let end = max(duration, peakEnd)
        let bounds: [(SpikePhase, TimeInterval, TimeInterval)] = [
            (.rise, 0, peakStart),
            (.peak, peakStart, peakEnd),
            (.recovery, peakEnd, end)
        ]
        return bounds.map { phase, from, to in
            SpikeSegment(phase: phase, start: from, end: to, avgHR: HRPoint.average(spans, from: from, to: to))
        }
    }

    /// Seconds from the last peak-phase reading to the first reading at or
    /// under resting + `recoveryMargin`; nil when the readings end before it
    /// gets there, so the card can say "hadn't settled by 15:02". Resting
    /// falls back to 65 when Health has none.
    static func recoveryTime(points: [HRPoint], restingHR: Int?) -> TimeInterval? {
        guard let threshold = peakThreshold(points),
              let peakEnd = points.lastIndex(where: { Double($0.bpm) >= threshold }) else {
            return nil
        }
        let target = (Moment.validHeartRate(restingHR) ?? Moment.fallbackRestingHR) + recoveryMargin
        for point in points.dropFirst(peakEnd + 1) where point.bpm <= target {
            return TimeInterval(point.offset - points[peakEnd].offset)
        }
        return nil
    }

    /// Halfway between the lowest and highest reading; nil for fewer than
    /// two readings or a flat curve.
    private static func peakThreshold(_ points: [HRPoint]) -> Double? {
        let values = points.map { $0.bpm }
        guard points.count >= 2, let low = values.min(), let high = values.max(), high > low else {
            return nil
        }
        return Double(low) + Double(high - low) / 2
    }
}
