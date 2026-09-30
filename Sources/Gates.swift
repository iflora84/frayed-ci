import SwiftUI

/// The birth-date check behind the 16+ rule (AgePolicy). Declared Age Range
/// comes back with the social phase; until then the date alone decides.
struct AgeGateView: View {
    let onResult: (AgeStatus) -> Void

    @State private var birthDate = Date()
    @State private var touched = false
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Wordmark(size: 44)
            Text("When were you born?")
                .font(Theme.title)
                .foregroundStyle(Theme.charcoal)
            Text("Frayed is for people 16 and over. Only your birth year is kept, on this iPhone, and it's never shared.")
                .font(Theme.body)
                .foregroundStyle(Theme.warmGrey)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Date of birth", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: birthDate) {
                    touched = true
                }
            Spacer()
            Button("Continue") {
                confirming = true
            }
            .buttonStyle(.frayedPrimary)
            .disabled(!touched)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
        .alert("Is this right?", isPresented: $confirming) {
            Button("Change", role: .cancel) {}
            Button("Confirm") {
                confirm()
            }
        } message: {
            Text("\(birthDate.formatted(date: .long, time: .omitted))\nThis can't be changed later.")
        }
    }

    private func confirm() {
        let calendar = Calendar.current
        guard AgePolicy.isAdult(birthDate: birthDate, now: Date(), calendar: calendar) else {
            onResult(AgeCheck.block())
            return
        }
        let year = calendar.component(.year, from: birthDate)
        onResult(AgeCheck.pass(birthYear: year))
    }
}

struct AgeBlockedView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Wordmark(size: 44)
            Text("Not yet")
                .font(Theme.title)
                .foregroundStyle(Theme.charcoal)
            Text("Frayed is for people 16 and over.")
                .font(Theme.body)
                .foregroundStyle(Theme.warmGrey)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// Face ID / passcode on launch and after the app has been in the background.
/// The content stays mounted while locked, only hidden, so tab selection and
/// open sheets survive a trip to another app. RootView re-locks on the
/// background; this only prompts. Sheets cover themselves with
/// `privacyCover(includesLock: true)`.
struct LockGate<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .opacity(model.isLocked ? 0 : 1)
            .allowsHitTesting(!model.isLocked)
            .accessibilityHidden(model.isLocked)
            .overlay {
                if model.isLocked {
                    LockScreen()
                }
            }
            .onAppear {
                promptIfActive()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    promptIfActive()
                }
            }
    }

    private func promptIfActive() {
        if scenePhase == .active {
            model.promptUnlockIfNeeded()
        }
    }
}

private struct LockScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Wordmark(size: 44)
            Text("Locked")
                .font(Theme.headline)
                .foregroundStyle(Theme.warmGrey)
            Button {
                Task { await model.unlock() }
            } label: {
                Label("Unlock", systemImage: "faceid")
            }
            .buttonStyle(.frayedOutline)
            .disabled(model.isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// Hides the screen whenever the scene is not active, so the app switcher
/// snapshot shows no data. Sheets and full-screen covers draw above the view
/// that presents them, so each one's root needs this too, with
/// `includesLock` so they also hide (and offer Unlock) while the app is
/// locked. The root view leaves it off: the age gate must never be covered.
struct PrivacyCoverModifier: ViewModifier {
    let includesLock: Bool

    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if includesLock && model.isLocked {
                LockScreen()
            } else if scenePhase != .active {
                PrivacyCover()
            }
        }
    }
}

extension View {
    /// Needs AppModel in the environment: apply it inside `.environmentObject`.
    func privacyCover(includesLock: Bool = false) -> some View {
        return modifier(PrivacyCoverModifier(includesLock: includesLock))
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.paper
            Wordmark(size: 44)
        }
        .ignoresSafeArea()
    }
}
