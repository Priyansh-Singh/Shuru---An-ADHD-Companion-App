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
            case .active:
                store.becameActive()
                Backup.shared.backUpIfStale(store)
            case .background:
                store.saveNow()
                Backup.shared.backUpInBackground(store)
            default: break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Created at launch so iOS can hand over "you arrived" events, even when it wakes the app in the background.
        _ = Places.shared
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The minimum-time note is a gentle buzz in the app instead of a banner.
        if notification.request.identifier == "shuru.limit.min" {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        let month = response.notification.request.content.userInfo["month"] as? String
        DispatchQueue.main.async {
            if id == "shuru.monthreview" {
                AppStore.shared.go(to: .calendar)
                AppStore.shared.monthReview = MonthReviewRequest(month: month ?? Day.monthKey(Day.today))
            } else if id.hasPrefix("shuru.checkin") {
                AppStore.shared.go(to: .hours)
            } else if id == "shuru.review" {
                AppStore.shared.go(to: .week)
            } else {
                AppStore.shared.go(to: .now)
            }
        }
        completionHandler()
    }
}
