import AppIntents
import Foundation

/// Run this from a Shortcuts automation ("When Instagram is opened") to get the pause screen.
struct PauseBeforeScrollingIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause before scrolling"
    static var description = IntentDescription("Opens Shuru’s pause screen. If you chose “Back to Instagram” recently, it sends you straight back.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared.requestPause()
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
            shortTitle: "Pause before scrolling",
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
