import SwiftUI

/// Age gate, then the lock, then first-run onboarding, then the tabs. Demo
/// mode skips them all. The UI mode picked at onboarding is injected here
/// so every screen reads `@Environment(\.uiMode)`.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(UIMode.key) private var modeName = UIMode.full.rawValue
    @AppStorage(OnboardingView.doneKey) private var onboarded = false
    @State private var age: AgeStatus = AgeCheck.current()

    var body: some View {
        Group {
            if model.isDemo {
                MainTabs()
            } else {
                switch age {
                case .unknown:
                    AgeGateView { age = $0 }
                case .blocked:
                    AgeBlockedView()
                case .adult:
                    LockGate {
                        if onboarded {
                            MainTabs()
                        } else {
                            OnboardingView { onboarded = true }
                        }
                    }
                }
            }
        }
        .uiMode(UIMode(rawValue: modeName) ?? .full)
        .privacyCover()
        .preferredColorScheme(.light)
        .tint(Theme.charcoal)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.sceneBecameActive()
            } else if phase == .background {
                model.lockForBackground()
            }
        }
    }
}

/// Feed · Recap · You. Recap is the middle and the launch tab. A native tab
/// bar cannot take Courier labels, so it stays plain in both modes.
private struct MainTabs: View {
    @EnvironmentObject private var model: AppModel
    @State private var page: MainTab = MainTabs.launchPage

    /// "-demo-screen feed|recap|you" picks the first tab, for CI screenshots.
    private static var launchPage: MainTab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo-screen"), i + 1 < args.count else {
            return .recap
        }
        switch args[i + 1] {
        case "feed": return .feed
        case "you": return .you
        default: return .recap
        }
    }

    var body: some View {
        TabView(selection: $page) {
            Tab("Feed", systemImage: "rectangle.stack", value: MainTab.feed) {
                screen(FeedView())
            }
            Tab("Recap", systemImage: "doc.text", value: MainTab.recap) {
                screen(RecapView())
            }
            Tab("You", systemImage: "person", value: MainTab.you) {
                screen(YouView())
            }
        }
        .onAppear {
            consumePendingTab()
        }
        .onChange(of: model.pendingTab) { _, _ in
            consumePendingTab()
        }
    }

    private func consumePendingTab() {
        guard let tab = model.pendingTab else {
            return
        }
        page = tab
        model.pendingTab = nil
    }

    /// Each tab root owns its NavigationStack (RecapView, YouView); Feed has no pushes.
    private func screen<Content: View>(_ content: Content) -> some View {
        content
            .background(Theme.paper.ignoresSafeArea())
    }
}
