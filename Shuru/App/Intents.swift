import AppIntents
import Foundation

/// Step 1 of the automation: checks without opening Shuru, so going back to an unlocked app never loops.
struct ShouldPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Check before opening"
    static var description = IntentDescription("Returns true if Shuru should pause you before this app. Use it in a “When an app is opened” automation, with App set to Shortcut Input.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App", description: "Set this to Shortcut Input so Shuru knows which app you opened.")
    var app: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Should Shuru pause \(\.$app)?")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: AppStore.shared.shouldPause(appInput: app))
    }
}

/// Step 2 of the automation: opens Shuru on the pause screen for that app.
struct PauseBeforeScrollingIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause before opening"
    static var description = IntentDescription("Opens Shuru’s pause screen for the app you were opening. Spend tokens there to unlock it for a while.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App", description: "Set this to Shortcut Input so Shuru knows which app you opened.")
    var app: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Pause before opening \(\.$app)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared.requestPause(appInput: app)
        return .result()
    }
}

struct OpenNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Show my next task"
    static var description = IntentDescription("Opens Shuru on the Now screen.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared.go(to: .now)
        return .result()
    }
}

struct ShuruShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseBeforeScrollingIntent(),
            phrases: ["Pause with \(.applicationName)"],
            shortTitle: "Pause before opening",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: OpenNowIntent(),
            phrases: ["What’s next in \(.applicationName)"],
            shortTitle: "Next task",
            systemImageName: "circle.dotted"
        )
    }
}
