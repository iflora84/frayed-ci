import SwiftUI

/// "This week's receipt": opens the weekly Courier receipt in a sheet.
/// Full draws it as a card row with the receipt glyph; Quiet as a plain row.
struct ReceiptEntry: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.uiMode) private var mode
    @State private var showing = false

    private var isSunday: Bool {
        return model.calendar.component(.weekday, from: Date()) == 1
    }

    var body: some View {
        Button {
            showing = true
        } label: {
            if mode == .quiet {
                HStack(spacing: 12) {
                    Text("This week's receipt")
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.charcoal)
                    Spacer()
                    if isSunday {
                        Highlight(text: "Ready")
                            .font(Theme.sans(13, weight: .medium))
                            .foregroundStyle(Theme.charcoal)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.warmGrey)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.charcoal)
                    Text("This week's receipt")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.charcoal)
                    Spacer()
                    if isSunday {
                        Highlight(text: "Ready")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.charcoal)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.warmGrey)
                }
                .frayedCard()
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            WeekReceiptSheet(receipt: model.weekReceipt(for: Date()))
        }
    }
}
