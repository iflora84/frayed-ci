import AppIntents
import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications

@main
struct FrayedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.model)
        }
    }
}

/// Owns the model so it exists before any scene, runs the background
/// refresh before the recap time, and receives the recap notification tap:
/// it opens the Recap tab, nothing else.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private(set) lazy var model = AppModel.fromLaunchArguments()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // LogFeltMomentIntent writes through the same model the screens read.
        let model = self.model
        AppDependencyManager.shared.add(dependency: model)
        // Must be registered before launch finishes; .main keeps the handler
        // on the model's actor.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppModel.refreshTaskIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                self.runRefresh(task)
            }
        }
        model.scheduleRecapNotification()
        return true
    }

    /// Writes today's recap, then books tomorrow's wake-up. iOS may cut the
    /// task short; the recap is then written on the next open instead.
    private func runRefresh(_ task: BGTask) {
        model.scheduleBackgroundRefresh(after: Date().addingTimeInterval(AppModel.backgroundLead))
        let work = Task { @MainActor in
            await self.model.refreshRecap(inBackground: true)
            if !Task.isCancelled {
                task.setTaskCompleted(success: true)
            }
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            if identifier == RecapNotification.identifier {
                self.model.pendingTab = .recap
            }
            completionHandler()
        }
    }
}
