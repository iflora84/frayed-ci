import CoreText
import SwiftUI
import UIKit

/// Sunroom tokens (design canvas A3S, direction A "Zine"): charcoal ink on
/// cream paper, apricot for what the heart did, sky for the night and the
/// come-down, butter for highlights, a cocoa rubber stamp for the day type.
/// Light-only: UIUserInterfaceStyle is Light, so every token is one colour.
enum Theme {
    // MARK: Paper and ink

    static let paper = hex(0xFBF5E9)
    static let card = hex(0xFFFDF7)
    /// Card borders, dividers and the timeline's axis.
    static let hairline = hex(0xE6DBC4)
    static let charcoal = hex(0x33302C)
    static let warmGrey = hex(0x6E6357)

    // MARK: Accents

    static let apricot = hex(0xDC7A32)
    /// Apricot dark enough to read as text on paper.
    static let apricotInk = hex(0xAE5220)
    static let apricotWash = hex(0xDC7A32, 0.32)
    static let sky = hex(0x5797C3)
    static let skyWash = hex(0xD9EAF4)
    /// Sky dark enough to read as text on paper.
    static let skyInk = hex(0x29648A)
    static let butter = hex(0xFBE58E)
    /// The rubber stamp: border and text of the day-type stamp.
    static let cocoa = hex(0x7B4B2A, 0.85)

    // MARK: Roles

    static let background = paper
    static let surface = card
    static let text = charcoal
    static let textSecondary = warmGrey
    static let accent = apricot
    /// Spikes on the strip and the still-spike count.
    static let spike = apricot
    /// Sleep, the night summary and rough nights.
    static let night = sky
    /// The hug reaction.
    static let hug = apricot
    /// The three phases of a spike curve.
    static let rise = butter
    static let peak = apricot
    static let recovery = sky
    /// The load number.
    static let loadNumber = apricotInk

    static let avatarFills: [Color] = [skyWash, butter, hex(0xF6DCC5), hex(0xE9E0CF), hex(0xDCE5D6)]

    /// Calm to frayed.
    static let loadGradient = Gradient(stops: [
        .init(color: sky, location: 0),
        .init(color: butter, location: 0.4),
        .init(color: apricot, location: 0.75),
        .init(color: apricotInk, location: 1)
    ])

    /// Bottom-left to top-right, as on the rings and badges.
    static let loadDiagonal = LinearGradient(gradient: loadGradient, startPoint: .bottomLeading, endPoint: .topTrailing)

    /// Zine cards: small radius, one-pixel charcoal or hairline border.
    static let cornerRadius: CGFloat = 6
    static let padding: CGFloat = 16

    // MARK: Type

    /// Bricolage Grotesque at its 96pt optical size, for the wordmark and
    /// titles. Ships in Bold and ExtraBold; `.heavy` and `.black` pick the
    /// latter, everything else Bold.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        _ = fontsReady
        return Font.custom(FontName.display(weight), size: size, relativeTo: style)
    }

    /// Bricolage Grotesque at its text optical size, for UI text.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        _ = fontsReady
        return Font.custom(FontName.sans(weight), size: size, relativeTo: style)
    }

    /// Courier Prime, for every number. Italic ships in one weight, so
    /// `italic: true` ignores `weight`.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        _ = fontsReady
        return Font.custom(italic ? FontName.monoItalic : FontName.mono(weight), size: size, relativeTo: style)
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        return mono(size, weight: weight)
    }

    static let wordmark: Font = display(34, weight: .heavy, relativeTo: .largeTitle)
    static let heroNumber: Font = mono(56, weight: .bold, relativeTo: .largeTitle)
    static let title: Font = display(30, relativeTo: .title)
    static let headline: Font = sans(17, weight: .semibold, relativeTo: .headline)
    static let body: Font = sans(16, relativeTo: .body)
    static let caption: Font = sans(12, weight: .medium, relativeTo: .caption)

    /// "4:07", "52:10", "1:02:30".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }

    /// Fixed English, 24-hour dates like the mockups and the moment titles,
    /// so a moment reads the same in the app and on its share card.
    /// "EEE d MMM · HH:mm" gives "Sun 12 Oct · 15:06".
    static func stamp(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    // MARK: Fonts

    /// PostScript names read from the bundled TTFs with fontTools. The files
    /// in Sources/Fonts carry the same names plus ".ttf". The Bricolage
    /// files are static instances cut from Google's variable font at
    /// wdth 100: opsz 96 for display, opsz 14 for text.
    enum FontName {
        static let displayBold = "BricolageGrotesque96pt-Bold"
        static let displayExtraBold = "BricolageGrotesque96pt-ExtraBold"
        static let sansRegular = "BricolageGrotesque-Regular"
        static let sansMedium = "BricolageGrotesque-Medium"
        static let sansSemiBold = "BricolageGrotesque-SemiBold"
        static let sansBold = "BricolageGrotesque-Bold"
        static let monoRegular = "CourierPrime-Regular"
        static let monoBold = "CourierPrime-Bold"
        static let monoItalic = "CourierPrime-Italic"

        static let all = [
            displayBold, displayExtraBold,
            sansRegular, sansMedium, sansSemiBold, sansBold,
            monoRegular, monoBold, monoItalic
        ]

        static func display(_ weight: Font.Weight) -> String {
            switch weight {
            case .heavy, .black: return displayExtraBold
            default: return displayBold
            }
        }

        static func sans(_ weight: Font.Weight) -> String {
            switch weight {
            case .bold, .heavy, .black: return sansBold
            case .semibold: return sansSemiBold
            case .medium: return sansMedium
            default: return sansRegular
            }
        }

        /// Courier Prime ships 400 and 700 only; semibold rounds up, medium
        /// stays regular because typewriter bold is a big jump.
        static func mono(_ weight: Font.Weight) -> String {
            switch weight {
            case .semibold, .bold, .heavy, .black: return monoBold
            default: return monoRegular
            }
        }
    }

    /// UIAppFonts registers the fonts at launch. If a file is ever missing
    /// from that list or lands in a subfolder, register it by hand so the
    /// app does not silently fall back to the system font.
    private static let fontsReady: Bool = {
        var ready = true
        for name in FontName.all where UIFont(name: name, size: 12) == nil {
            let found = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            guard let url = found, CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) else {
                ready = false
                continue
            }
        }
        return ready
    }()

    private static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
