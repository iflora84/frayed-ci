import SwiftUI

/// Minute heart rate drawn as a line over a dashed resting rule. The whole
/// day on Recap (a dot on every spike's peak, tap one to open it) and one
/// spike's window in its detail (the elevated stretch shaded).
struct HeartCurve: View {
    let beats: [DayRecap.Beat]
    let span: ClosedRange<Date>
    let resting: Int
    var spikes: [DayRecap.Spike] = []
    var shaded: ClosedRange<Date>? = nil
    var tickFormat = "h a"
    var onSelect: ((DayRecap.Spike) -> Void)? = nil

    /// Readings further apart than this are a gap (Watch off), not a line.
    private static let gap: TimeInterval = 20 * 60

    private var bpmRange: ClosedRange<Double> {
        let values = beats.map { $0.bpm } + spikes.map { $0.peak } + [resting]
        let low = Double(values.min() ?? resting) - 4
        let high = Double(values.max() ?? resting) + 6
        return low...max(high, low + 20)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let size = geo.size
                let range = bpmRange
                ZStack(alignment: .topLeading) {
                    Canvas { context, canvasSize in
                        draw(in: &context, size: canvasSize)
                    }
                    ForEach(spikes, id: \.id) { spike in
                        marker(spike)
                            .position(point(spike.peakAt, Double(spike.peak), size, range))
                    }
                }
            }
            ticks
        }
        .accessibilityElement(children: .contain)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let range = bpmRange
        if let shaded {
            let x0 = x(shaded.lowerBound, size.width)
            let x1 = x(shaded.upperBound, size.width)
            context.fill(Path(CGRect(x: x0, y: 0, width: max(x1 - x0, 2), height: size.height)),
                         with: .color(Theme.apricotWash.opacity(0.5)))
        }

        let restY = y(Double(resting), size.height, range)
        var rule = Path()
        rule.move(to: CGPoint(x: 0, y: restY))
        rule.addLine(to: CGPoint(x: size.width, y: restY))
        context.stroke(rule, with: .color(Theme.skyInk.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        var line = Path()
        var previous: Date? = nil
        for beat in beats where span.contains(beat.at) {
            let p = point(beat.at, Double(beat.bpm), size, range)
            if let previous, beat.at.timeIntervalSince(previous) <= HeartCurve.gap {
                line.addLine(to: p)
            } else {
                line.move(to: p)
            }
            previous = beat.at
        }
        context.stroke(line, with: .color(Theme.charcoal),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder
    private func marker(_ spike: DayRecap.Spike) -> some View {
        let dot = Circle()
            .fill(color(spike.bucket))
            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 1.5))
            .frame(width: 10, height: 10)
        if let onSelect {
            Button {
                onSelect(spike)
            } label: {
                dot.frame(width: 32, height: 32).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(spike))
            .accessibilityHint("Opens this spike")
        } else {
            dot.accessibilityHidden(true)
        }
    }

    private var ticks: some View {
        HStack {
            ForEach(Array(tickDates.enumerated()), id: \.offset) { index, date in
                Text(Theme.stamp(date, tickFormat).lowercased())
                if index < tickDates.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .font(Theme.mono(10))
        .foregroundStyle(Theme.warmGrey)
        .accessibilityHidden(true)
    }

    private var tickDates: [Date] {
        let length = span.upperBound.timeIntervalSince(span.lowerBound)
        return (0...3).map { span.lowerBound.addingTimeInterval(length * Double($0) / 3) }
    }

    private func color(_ bucket: DayRecap.Bucket) -> Color {
        switch bucket {
        case .still: return Theme.apricotInk
        case .workout, .moving: return Theme.warmGrey
        case .inBed: return Theme.skyInk
        }
    }

    private func accessibilityLabel(_ spike: DayRecap.Spike) -> String {
        let clock = FrayedFormat.clock(spike.peakAt)
        return "\(clock.time) \(clock.meridiem), \(StoryWords.title(spike)), peak \(spike.peak)"
    }

    private func x(_ date: Date, _ width: CGFloat) -> CGFloat {
        let length = max(span.upperBound.timeIntervalSince(span.lowerBound), 1)
        return width * CGFloat(date.timeIntervalSince(span.lowerBound) / length)
    }

    private func y(_ bpm: Double, _ height: CGFloat, _ range: ClosedRange<Double>) -> CGFloat {
        let fraction = (bpm - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height * CGFloat(1 - fraction)
    }

    private func point(_ date: Date, _ bpm: Double, _ size: CGSize, _ range: ClosedRange<Double>) -> CGPoint {
        return CGPoint(x: x(date, size.width), y: y(bpm, size.height, range))
    }
}
