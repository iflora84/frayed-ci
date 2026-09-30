import SwiftUI

/// Which of the two looks the user picked at onboarding (design canvas rows
/// Q and R). Same data, same friends; only the amount on screen changes.
enum UIMode: String, CaseIterable, Identifiable {
    case quiet, full

    static let key = "ui.mode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet: return "Quiet"
        case .full: return "Full"
        }
    }

    var blurb: String {
        switch self {
        case .quiet: return "One thing per screen. Lots of air. The day in a sentence, and the rest a tap away."
        case .full: return "The whole day, in order. Receipts, pay stubs, permission slips. Every spike and how it came down."
        }
    }
}

private struct UIModeKey: EnvironmentKey {
    static let defaultValue = UIMode.full
}

extension EnvironmentValues {
    var uiMode: UIMode {
        get { self[UIModeKey.self] }
        set { self[UIModeKey.self] = newValue }
    }
}

extension View {
    func uiMode(_ mode: UIMode) -> some View {
        return environment(\.uiMode, mode)
    }
}

// MARK: Cards

/// The one card in the app: cream surface, hairline border, 12pt corners.
/// Quiet mode uses the same card with more padding; nothing is ever tilted,
/// torn or taped.
struct FrayedCard: ViewModifier {
    var padding: CGFloat
    var fill: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

extension View {
    func frayedCard(padding: CGFloat = 14, fill: Color = Theme.card) -> some View {
        return modifier(FrayedCard(padding: padding, fill: fill))
    }

    /// A block inside a card (pay stub, permission slip, the mini story list).
    func frayedInset(padding: CGFloat = 10) -> some View {
        return modifier(FrayedCard(padding: padding, fill: Theme.paper))
    }
}

// MARK: Text

/// Small Courier caps: "RECAP · THU SEP 24", "TODAY, IN ORDER".
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.warmGrey

    init(_ text: String, color: Color = Theme.warmGrey) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11))
            .kerning(0.7)
            .foregroundStyle(color)
    }
}

/// Apricot outline pill for the day type and a spike's tag: never rotated.
struct DayTypePill: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(Theme.apricotInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Theme.apricotInk, lineWidth: 1))
            .lineLimit(1)
            .fixedSize()
    }
}

/// Butter highlighter behind one phrase: "came down". One per screen.
struct Highlight: View {
    let text: String

    var body: some View {
        Text(text)
            .padding(.horizontal, 5)
            .padding(.bottom, 1)
            .background(Theme.butter)
    }
}

/// "frayed", evenly tracked. The app icon is this whole word on the tile.
struct Wordmark: View {
    var size: CGFloat = 20
    var color: Color = Theme.charcoal

    var body: some View {
        Text("frayed")
            .kerning(-0.025 * size)
            .font(Theme.display(size, weight: .heavy, relativeTo: .largeTitle))
            .foregroundStyle(color)
            .accessibilityLabel("Frayed")
    }
}

/// The charcoal rule under every Full-mode screen header, with the wordmark
/// on the left and a Courier stamp on the right.
struct ScreenHeader<Trailing: View>: View {
    let stamp: String?
    let trailing: Trailing

    init(stamp: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.stamp = stamp
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Wordmark()
            Spacer()
            if let stamp {
                Eyebrow(stamp)
            }
            trailing
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.charcoal).frame(height: 1)
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(stamp: String? = nil) {
        self.init(stamp: stamp) { EmptyView() }
    }
}

// MARK: Buttons

/// Charcoal block button: "Share today's card", "Continue".
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(16, weight: .bold))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.charcoal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Outlined capsule: "Play the come-down", "Breathe", reaction chips.
struct OutlineButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(13, weight: .bold))
            .foregroundStyle(selected ? Theme.charcoal : Theme.warmGrey)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(selected ? Theme.apricotWash.opacity(0.5) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Theme.charcoal : Theme.warmGrey, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var frayedPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var frayedOutline: OutlineButtonStyle { OutlineButtonStyle() }
    static func frayedOutline(selected: Bool) -> OutlineButtonStyle { OutlineButtonStyle(selected: selected) }
}

/// The 988 line that every screen keeps within reach (SPEC 1.6).
struct CrisisLine: View {
    var text = "Heavier than a recap can hold? Call or text 988, any time."

    var body: some View {
        Link(destination: URL(string: "tel:988")!) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "phone")
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(Theme.sans(13))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Theme.charcoal)
        }
        .accessibilityLabel("Call or text 988, the Suicide and Crisis Lifeline")
    }
}

// MARK: Marks

/// The small rise-and-settle mark on a story-list row: a flat line, one
/// hump whose height is the spike's magnitude on a shared scale, and a
/// blue dot where the heart got back near resting. Workouts draw a jagged
/// plateau in warm grey instead.
struct SettleMark: View {
    enum Kind {
        case still, workout, inBed, flat
    }

    let kind: Kind
    /// 0...1 of the shared scale (magnitude / 60 clamped).
    var height: Double = 0.5
    /// 0...1 where the recovery dot sits; nil draws no dot.
    var settledAt: Double? = 0.6

    var body: some View {
        Canvas { context, size in
            let base = size.height - 3
            let top = max(2, base - CGFloat(min(max(height, 0), 1)) * (base - 2))
            var path = Path()
            path.move(to: CGPoint(x: 0, y: base))
            switch kind {
            case .flat:
                path.addLine(to: CGPoint(x: size.width, y: base))
            case .workout:
                let x0 = size.width * 0.15, x1 = size.width * 0.8
                path.addLine(to: CGPoint(x: x0, y: base))
                var x = x0
                var up = true
                while x < x1 {
                    x += (x1 - x0) / 6
                    path.addLine(to: CGPoint(x: min(x, x1), y: up ? top : top + 3))
                    up.toggle()
                }
                path.addLine(to: CGPoint(x: x1, y: base))
                path.addLine(to: CGPoint(x: size.width, y: base))
            case .still, .inBed:
                let rise = size.width * 0.25
                let settle = size.width * CGFloat(settledAt ?? 0.6)
                path.addLine(to: CGPoint(x: rise * 0.5, y: base))
                path.addLine(to: CGPoint(x: rise, y: top))
                path.addCurve(to: CGPoint(x: settle, y: base),
                              control1: CGPoint(x: rise + (settle - rise) * 0.3, y: top),
                              control2: CGPoint(x: rise + (settle - rise) * 0.7, y: base - 1))
                path.addLine(to: CGPoint(x: size.width, y: base))
            }
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            let wash: Color
            switch kind {
            case .still: wash = Theme.apricotWash
            case .workout: wash = Theme.apricot.opacity(0.14)
            case .inBed: wash = Theme.skyWash
            case .flat: wash = .clear
            }
            context.fill(fill, with: .color(wash))
            context.stroke(path, with: .color(kind == .workout ? Theme.warmGrey : Theme.charcoal),
                           style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            if kind != .flat, let settledAt {
                let x = kind == .workout ? size.width * 0.8 : size.width * CGFloat(settledAt)
                let dot = CGRect(x: x - 3.4, y: base - 3.4, width: 6.8, height: 6.8)
                context.fill(Path(ellipseIn: dot), with: .color(Theme.card))
                context.fill(Path(ellipseIn: dot.insetBy(dx: 1.1, dy: 1.1)), with: .color(Theme.skyInk))
            }
        }
        .frame(width: 40, height: 16)
        .accessibilityHidden(true)
    }
}

/// Initials or the anonymous heron on a hairline disc.
struct Avatar: View {
    let initials: String
    var size: CGFloat = 32
    var anonymous = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.hairline)
            if anonymous {
                Image(systemName: "bird")
                    .font(.system(size: size * 0.5, weight: .regular))
                    .foregroundStyle(Theme.charcoal)
            } else {
                Text(initials)
                    .font(Theme.sans(size * 0.4, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: Formatting

enum FrayedFormat {
    /// "6 min", "1 h 12".
    static func minutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
        }
        return "\(minutes) min"
    }

    /// "8:15" with a small "am"/"pm" handled by the caller: returns ("8:15", "am").
    static func clock(_ date: Date, calendar: Calendar = .current) -> (time: String, meridiem: String) {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return (String(format: "%d:%02d", h12, minute), hour < 12 ? "am" : "pm")
    }

    /// "Thu Sep 24".
    static func dayStamp(_ date: Date) -> String {
        return Theme.stamp(date, "EEE MMM d")
    }

    /// "Thursday, September 24".
    static func longDay(_ date: Date) -> String {
        return Theme.stamp(date, "EEEE, MMMM d")
    }
}
