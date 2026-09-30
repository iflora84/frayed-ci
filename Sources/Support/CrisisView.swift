import SwiftUI

/// The Help destination: three lines to reach a person, in Quiet's voice
/// whatever the UI mode. Presented as a sheet from Settings and linked from
/// the recap footer.
struct CrisisView: View {
    var asSheet = false

    @Environment(\.dismiss) private var dismiss

    private struct Line: Identifiable {
        let title: String
        let detail: String
        let url: URL

        var id: String { title }
    }

    private static let lines: [Line] = [
        Line(title: "Call or text 988",
             detail: "Suicide and Crisis Lifeline, US, 24/7, for anyone, not only emergencies",
             url: URL(string: "tel:988")!),
        Line(title: "Text HOME to 741741",
             detail: "Crisis Text Line",
             url: URL(string: "sms:741741&body=HOME") ?? URL(string: "sms:741741")!),
        Line(title: "Outside the US",
             detail: "findahelpline.com lists lines by country",
             url: URL(string: "https://findahelpline.com")!)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("If today is heavier than a recap can hold")
                    .font(Theme.display(26, weight: .bold, relativeTo: .title))
                    .foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, asSheet ? 32 : 8)

                VStack(spacing: 0) {
                    ForEach(CrisisView.lines) { line in
                        Link(destination: line.url) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(line.title)
                                        .font(Theme.sans(16, weight: .bold))
                                        .foregroundStyle(Theme.charcoal)
                                    Text(line.detail)
                                        .font(Theme.sans(13))
                                        .foregroundStyle(Theme.warmGrey)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.warmGrey)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                            .padding(.vertical, 12)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Theme.hairline).frame(height: 1)
                            }
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                .padding(.top, 28)

                Text("Frayed reads your heart, not your mind. It never decides what you're going through, and it's not a substitute for a person.")
                    .font(Theme.sans(16))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)

                if asSheet {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.frayedPrimary)
                    .padding(.top, 36)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Crisis resources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
