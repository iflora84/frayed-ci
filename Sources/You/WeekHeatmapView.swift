import SwiftUI
import UIKit

/// The Grid on You (canvas R-You): this week and last, one 30 pt square per
/// day, coloured by how fast the day came down. Never by how good it was.
struct WeekHeatmapView: View {
    let ledgers: [DayLedger]
    let calendar: Calendar

    private static let skyLight = Color(.sRGB, red: 185 / 255, green: 215 / 255, blue: 234 / 255, opacity: 1)
    private static let paperMid = Color(.sRGB, red: 239 / 255, green: 231 / 255, blue: 214 / 255, opacity: 1)
    private static let apricotLight = Color(.sRGB, red: 241 / 255, green: 195 / 255, blue: 160 / 255, opacity: 1)

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    private enum Cell {
        case settled(Color, word: String, bar: String)
        case watchOff
        case notYet

        var word: String {
            switch self {
            case .settled(_, let word, _): return word
            case .watchOff: return "Watch off"
            case .notYet: return "not yet"
            }
        }

        var bar: String {
            switch self {
            case .settled(_, _, let bar): return bar
            case .watchOff: return "-"
            case .notYet: return "·"
            }
        }
    }

    private struct WeekRow {
        let number: Int
        let cells: [Cell]
        let todayIndex: Int?
    }

    var body: some View {
        let rows = weekRows()
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("The Grid · what kind of days")
                Spacer()
                Button {
                    UIPasteboard.general.string = rows.first.map { $0.cells.map { $0.bar }.joined() } ?? ""
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text("COPY WEEK")
                            .font(Theme.mono(11, weight: .bold))
                            .kerning(0.7)
                            .underline()
                    }
                    .foregroundStyle(Theme.charcoal)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 40, height: 14)
                    ForEach(0..<7, id: \.self) { column in
                        let isToday = rows.first?.todayIndex == column
                        Text(WeekHeatmapView.letters[column])
                            .font(Theme.mono(11, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Theme.charcoal : Theme.warmGrey)
                            .frame(width: 30)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 8) {
                        Text("WK \(row.number)")
                            .font(Theme.mono(11, weight: index == 0 ? .bold : .regular))
                            .kerning(0.7)
                            .foregroundStyle(index == 0 ? Theme.charcoal : Theme.warmGrey)
                            .frame(width: 40, alignment: .leading)
                        ForEach(0..<7, id: \.self) { column in
                            square(row.cells[column], isToday: row.todayIndex == column)
                        }
                    }
                }
            }
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(rows))

            HStack(spacing: 8) {
                Text("SLOW TO SETTLE")
                LinearGradient(stops: [
                    .init(color: Theme.apricot, location: 0),
                    .init(color: WeekHeatmapView.apricotLight, location: 0.25),
                    .init(color: WeekHeatmapView.paperMid, location: 0.5),
                    .init(color: WeekHeatmapView.skyLight, location: 0.75),
                    .init(color: Theme.sky, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
                .frame(width: 120, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text("FAST")
            }
            .font(Theme.mono(11))
            .kerning(0.2)
            .foregroundStyle(Theme.warmGrey)
            .padding(.top, 9)

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Theme.warmGrey, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                        .frame(width: 10, height: 10)
                    Text("WATCH OFF")
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                        .frame(width: 10, height: 10)
                    Text("NOT YET")
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WeekHeatmapView.skyLight)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.charcoal, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                    Text("TODAY")
                }
            }
            .font(Theme.mono(11))
            .kerning(0.2)
            .foregroundStyle(Theme.warmGrey)
            .padding(.top, 5)

            Text("Colour is how fast the day came down, not how good it was.")
                .font(Theme.sans(11))
                .foregroundStyle(Theme.warmGrey)
                .padding(.top, 5)
        }
    }

    @ViewBuilder
    private func square(_ cell: Cell, isToday: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            switch cell {
            case .settled(let color, _, _):
                shape.fill(color)
            case .watchOff:
                shape.fill(Theme.card)
                shape.strokeBorder(Theme.warmGrey, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            case .notYet:
                shape.strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                Text("·")
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.warmGrey)
            }
            if isToday {
                shape.strokeBorder(Theme.charcoal, lineWidth: 1.5)
            }
        }
        .frame(width: 30, height: 30)
    }

    // MARK: Data

    private func weekRows() -> [WeekRow] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let sinceMonday = (weekday + 5) % 7
        guard let thisMonday = calendar.date(byAdding: .day, value: -sinceMonday, to: today),
              let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday) else {
            return []
        }
        return [row(startingMonday: thisMonday, today: today), row(startingMonday: lastMonday, today: today)]
    }

    private func row(startingMonday monday: Date, today: Date) -> WeekRow {
        var cells: [Cell] = []
        var todayIndex: Int?
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            if calendar.isDate(day, inSameDayAs: today) {
                todayIndex = offset
            }
            if day > today {
                cells.append(.notYet)
                continue
            }
            let ledger = ledgers.first { calendar.isDate($0.day, inSameDayAs: day) }
            cells.append(cell(for: ledger))
        }
        return WeekRow(number: calendar.component(.weekOfYear, from: monday), cells: cells, todayIndex: todayIndex)
    }

    private func cell(for ledger: DayLedger?) -> Cell {
        guard let ledger else {
            return .watchOff
        }
        guard let median = ledger.recoveryMedianMinutes else {
            return ledger.worn ? .settled(WeekHeatmapView.paperMid, word: "middling", bar: "▃") : .watchOff
        }
        if median <= 5 {
            return .settled(Theme.sky, word: "fast", bar: "▁")
        }
        if median <= 8 {
            return .settled(WeekHeatmapView.skyLight, word: "faster than usual", bar: "▂")
        }
        if median <= 11 {
            return .settled(WeekHeatmapView.paperMid, word: "middling", bar: "▃")
        }
        if median <= 14 {
            return .settled(WeekHeatmapView.apricotLight, word: "slower than usual", bar: "▄")
        }
        return .settled(Theme.apricot, word: "slow", bar: "▅")
    }

    private func accessibilitySummary(_ rows: [WeekRow]) -> String {
        let parts = rows.enumerated().map { index, row -> String in
            let days = row.cells.map { $0.word }.joined(separator: ", ")
            return index == 0 ? "Week \(row.number), Monday to Sunday: \(days)." : "Week \(row.number): \(days)."
        }
        return "Heatmap of how fast each day came down. " + parts.joined(separator: " ")
    }
}
