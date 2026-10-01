import Foundation

/// Called It (IDEAS 2.8): the user stamps "felt it" from Siri or a Shortcut,
/// and the recap says whether the Watch backed them. The scorecard runs one
/// way only, the user's calls checked against the Watch, never the other
/// way, and the copy never says "missed" or "false alarm".
enum FeltMatcher {
    /// Background readings come about every 5 min, so a stamp counts for a
    /// spike up to 10 min either side of it.
    static let window: TimeInterval = 10 * 60

    enum Outcome: Equatable {
        /// A spike of any bucket overlaps the stamp's window.
        case backed(spikeId: String, bucket: DayRecap.Bucket)
        /// Readings near the stamp, none of them up.
        case quiet
        /// No reading within the window: the Watch was off or elsewhere.
        case blind
    }

    struct Summary: Equatable {
        var called = 0
        var backed = 0
        var quiet = 0
        var blind = 0
    }

    /// The spike nearest the stamp whose [start, settled] widened by the
    /// window contains it; else quiet or blind by the readings around it.
    static func match(_ stamp: Date, spikes: [DayRecap.Spike], beats: [DayRecap.Beat]) -> Outcome {
        let hits = spikes.filter { spike in
            let settled = max(spike.recoveredAt ?? spike.end, spike.end)
            return stamp >= spike.start.addingTimeInterval(-window) && stamp <= settled.addingTimeInterval(window)
        }
        if let best = hits.min(by: { abs($0.peakAt.timeIntervalSince(stamp)) < abs($1.peakAt.timeIntervalSince(stamp)) }) {
            return .backed(spikeId: best.id, bucket: best.bucket)
        }
        let seen = beats.contains { abs($0.at.timeIntervalSince(stamp)) <= window }
        return seen ? .quiet : .blind
    }

    static func summarize(_ stamps: [Date], recap: DayRecap) -> Summary {
        var summary = Summary()
        for stamp in stamps {
            summary.called += 1
            switch match(stamp, spikes: recap.spikes, beats: recap.beats ?? []) {
            case .backed: summary.backed += 1
            case .quiet: summary.quiet += 1
            case .blind: summary.blind += 1
            }
        }
        return summary
    }

    /// One recap line; nil when nothing was called.
    static func line(_ s: Summary) -> String? {
        guard s.called > 0 else {
            return nil
        }
        if s.called == 1 {
            if s.backed == 1 {
                return "You called one today. The Watch backed you."
            }
            if s.quiet == 1 {
                return "You called one today. Readings there, none of them up. Feeling it still counts."
            }
            return "You called one today. No reading within 10 min of it. The Watch was elsewhere."
        }
        var out = "You called \(s.called) today. "
        switch s.backed {
        case 0: out += "The Watch didn't back any of them."
        case s.called: out += "The Watch backed you on every one."
        default: out += "The Watch backed you on \(s.backed)."
        }
        let rest = s.called - s.backed
        if rest > 0 {
            out += s.quiet == 0 ? " It just didn't see the rest." : " Feeling it still counts."
        }
        return out
    }
}
