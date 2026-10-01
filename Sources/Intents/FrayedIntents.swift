import AppIntents
import Foundation

/// "I felt it" from Siri, Spotlight, the Action button or a Shortcut
/// (IDEAS 2.8). Runs in the app's process without opening it; the stamp is
/// matched against the Watch when the recap is shown.
struct LogFeltMomentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a spike"
    static let description = IntentDescription("Stamps this moment as one you felt. Tonight's recap says whether the Watch saw it too.")
    static let openAppWhenRun = false

    @Parameter(title: "What was it?")
    var tag: SpikeTagEntity?

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try model.logFeltMoment(tag: tag?.tag)
        return .result(dialog: "Noted. Tonight's recap will say if the Watch saw it too.")
    }
}

/// The user's own words for a spike, offered as Siri's options.
enum SpikeTagEntity: String, AppEnum {
    case meeting, argument, deadline, panic, excited, somethingGood, caffeine, noIdea

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Word"
    static let caseDisplayRepresentations: [SpikeTagEntity: DisplayRepresentation] = [
        .meeting: "Meeting",
        .argument: "Argument",
        .deadline: "Deadline",
        .panic: "Panic",
        .excited: "Excited",
        .somethingGood: "Something good",
        .caffeine: "Caffeine",
        .noIdea: "No idea"
    ]

    var tag: SpikeTag? {
        return SpikeTag(rawValue: rawValue)
    }
}

struct FrayedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFeltMomentIntent(),
            phrases: [
                "Log a spike in \(.applicationName)",
                "I felt it in \(.applicationName)",
                "\(.applicationName), I felt that"
            ],
            shortTitle: "Log a spike",
            systemImageName: "waveform.path.ecg"
        )
    }
}
