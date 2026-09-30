import SwiftUI

/// Canvas R-Receipt: the week as a thermal-paper bill, 312 pt wide on
/// paper, drawn at 390 pt wide for the share card. Plain values only.
struct WeekReceiptView: View {
    static let size = CGSize(width: 390, height: 693)

    let receipt: WeekReceipt

    var body: some View {
        ZStack(alignment: .top) {
            Theme.paper
            bill
                .padding(.top, 18)
                .padding(.bottom, 24)
        }
        .frame(width: WeekReceiptView.size.width)
        .frame(minHeight: WeekReceiptView.size.height)
        .environment(\.colorScheme, .light)
    }

    private var bill: some View {
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                Wordmark(size: 40)
                mono("Weekly receipt · \(receipt.rangeLabel) · Wk \(receipt.weekNumber)", size: 11, color: Theme.warmGrey)
            }

            rule(top: 12, bottom: 8)
            row(mono("Day", color: Theme.warmGrey), mono("Came down", color: Theme.warmGrey))
            ForEach(Array(receipt.lines.enumerated()), id: \.element.id) { index, line in
                dayRow(line)
                    .padding(.top, index == 0 ? 5 : 3)
            }

            rule(top: 10, bottom: 8)
            VStack(spacing: 3) {
                row(mono("Spikes, sitting still"), mono("\(receipt.stillSpikes)"))
                row(mono("Every one came down"), mono(receipt.everyOneCameDown ? "yes" : "no"))
                row(mono("Came down, avg"), mono(receipt.cameDownAverageMinutes.map { "~ \($0) min" } ?? "\u{2014}"))
                row(mono("Fastest day"), mono(fastest))
                row(mono("Slept, avg"), mono(receipt.asleepAverageMinutes.map { "\($0 / 60)h \(String(format: "%02d", $0 % 60))m" } ?? "\u{2014}"))
                row(mono("Calmest"), mono(calmest))
                row(mono("Watch attendance"), mono("\(receipt.wornDays) of 7 days"))
                row(mono("Tip"), mono("none."))
            }
            Text("Nobody tips a chair.")
                .font(Theme.mono(13))
                .foregroundStyle(Theme.charcoal)
                .padding(.top, 8)

            rule(top: 10, bottom: 12)
            VStack(spacing: 5) {
                barcode
                Text(receipt.receiptNumber.uppercased())
                    .font(Theme.mono(11))
                    .kerning(2)
                    .foregroundStyle(Theme.warmGrey)
            }
            mono("Thank you for sitting still", size: 12, weight: .bold)
                .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 26, trailing: 24))
        .frame(width: 312)
        .background(Theme.card, in: ZigzagEdge())
        .compositingGroup()
        .shadow(color: Theme.apricotInk.opacity(0.16), radius: 0, x: 0, y: 2)
        .shadow(color: Theme.charcoal.opacity(0.12), radius: 7, x: 0, y: 8)
    }

    private var fastest: String {
        guard let line = receipt.fastest, let minutes = line.recoveryMinutes else {
            return "\u{2014}"
        }
        return "\(line.weekday) · \(minutes) min"
    }

    private var calmest: String {
        guard let calmest = receipt.calmest else {
            return "\u{2014}"
        }
        return "\(calmest.line.weekday) \(Theme.stamp(calmest.at, "h:mm")) · \(calmest.bpm) bpm"
    }

    private func dayRow(_ line: WeekReceipt.Line) -> some View {
        let dim = !line.worn
        let minutes = line.recoveryMinutes.map { "\($0) min" } ?? "\u{2014}"
        return row(
            Text("\(mono(line.weekday, color: dim ? Theme.warmGrey : Theme.charcoal))\(mono(" " + line.typeLabel, color: Theme.warmGrey))"),
            mono(minutes, color: dim ? Theme.warmGrey : Theme.charcoal)
        )
    }

    private func row(_ left: Text, _ right: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            left.lineLimit(1)
            Spacer(minLength: 8)
            right.lineLimit(1)
        }
    }

    private func mono(_ text: String, size: CGFloat = 12.5, weight: Font.Weight = .regular, color: Color = Theme.charcoal) -> Text {
        return Text(text.uppercased())
            .font(Theme.mono(size, weight: weight))
            .kerning(0.5)
            .foregroundStyle(color)
    }

    private func rule(top: CGFloat, bottom: CGFloat) -> some View {
        DashedRule(color: Theme.hairline)
            .padding(.top, top)
            .padding(.bottom, bottom)
    }

    /// One bar per day, wider on days with more spikes.
    private var barcode: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(receipt.barcodeWidths.enumerated()), id: \.offset) { _, width in
                Rectangle()
                    .fill(Theme.charcoal)
                    .frame(width: CGFloat(max(width, 1)) * 2, height: 30)
            }
        }
        .frame(height: 30)
        .accessibilityLabel("Barcode drawn from the seven days: one bar per day, wider on days with more spikes")
    }
}

/// Thermal-paper edge: 9 pt teeth, 5 pt deep, top and bottom.
struct ZigzagEdge: Shape {
    var tooth: CGFloat = 9
    var depth: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        var x = rect.minX
        var down = false
        while x < rect.maxX {
            x = min(x + tooth, rect.maxX)
            down.toggle()
            path.addLine(to: CGPoint(x: x, y: down ? rect.minY + depth : rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        x = rect.maxX
        down = false
        while x > rect.minX {
            x = max(x - tooth, rect.minX)
            down.toggle()
            path.addLine(to: CGPoint(x: x, y: down ? rect.maxY - depth : rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// The receipt in a sheet with Share and Done, from You and the Sunday nudge.
struct WeekReceiptSheet: View {
    let receipt: WeekReceipt

    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                WeekReceiptView(receipt: receipt)
                    .frame(maxWidth: .infinity)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("This week's receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        shareItem = CardRenderer.image(WeekReceiptView(receipt: receipt),
                                                       width: WeekReceiptView.size.width,
                                                       height: WeekReceiptView.size.height).map { ShareItem(image: $0) }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.image])
            }
        }
        .tint(Theme.charcoal)
    }
}
