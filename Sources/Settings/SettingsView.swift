import SwiftUI

/// Settings, reached from You. Plain sections on paper with hairlines in
/// both modes; nothing here needs decoration.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(UIMode.key) private var modeRaw = UIMode.full.rawValue
    @State private var confirmingDelete = false

    static let privacyURL = URL(string: "https://iflora84.github.io/frayed-privacy")!
    static let supportURL = URL(string: "mailto:zhenyitong84@gmail.com?subject=Frayed%20support")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var modeBinding: Binding<UIMode> {
        Binding(
            get: { UIMode(rawValue: modeRaw) ?? .full },
            set: { modeRaw = $0.rawValue }
        )
    }

    private var recapTime: Binding<Date> {
        Binding(
            get: {
                let components = DateComponents(hour: model.recapSchedule.hour, minute: model.recapSchedule.minute)
                return model.calendar.date(from: components) ?? Date()
            },
            set: { date in
                let parts = model.calendar.dateComponents([.hour, .minute], from: date)
                model.recapSchedule = RecapNotification.Schedule(hour: parts.hour ?? RecapNotification.defaultHour,
                                                                 minute: parts.minute ?? RecapNotification.defaultMinute)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("Look") {
                    Picker("Look", selection: modeBinding) {
                        ForEach(UIMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 8)
                }

                section("Recap time") {
                    DatePicker("Recap time", selection: recapTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()
                }

                section("Face ID lock") {
                    Toggle("Ask for Face ID when Frayed opens", isOn: $model.lockEnabled)
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.charcoal)
                        .tint(Theme.charcoal)
                        .frame(minHeight: 44)
                }

                section("Help") {
                    NavigationLink {
                        CrisisView(asSheet: false)
                    } label: {
                        row("Crisis resources", trailing: "988")
                    }
                    .buttonStyle(.plain)
                    Link(destination: SettingsView.privacyURL) {
                        row("Privacy policy", trailing: nil)
                    }
                    Link(destination: SettingsView.supportURL) {
                        row("Support", trailing: nil)
                    }
                }

                section("Your data") {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Text("Delete all data")
                            .font(Theme.sans(16))
                            .foregroundStyle(Theme.apricotInk)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Frayed reads background heart rate, HRV and sleep from Apple Health. Nothing is posted until you choose to.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.warmGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)

                Text("Version \(version)")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.warmGrey)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Theme.paper, for: .navigationBar)
        .tint(Theme.charcoal)
        .confirmationDialog("Delete all data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) {
                model.deleteAllData()
            }
        } message: {
            Text("Removes every recap and moment from this iPhone. Apple Health is untouched.")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.warmGrey)
                .padding(.top, 20)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private func row(_ title: String, trailing: String?) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.charcoal)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.charcoal)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.warmGrey)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
