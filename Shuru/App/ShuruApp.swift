import SwiftUI
import UserNotifications

@main
struct ShuruApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(store.data.settings.appearance.colorScheme)
                .tint(Theme.accent(store.data.settings.palette))
                .onOpenURL { url in store.handle(url: url) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.becameActive()
            case .background: store.saveNow()
            default: break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            AppStore.shared.go(to: id.hasPrefix("shuru.checkin") ? .hours : .now)
        }
        completionHandler()
    }
}
