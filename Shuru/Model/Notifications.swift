import Foundation
import UserNotifications

/// Local notifications only: hourly check-ins and timed routines.
/// These work in sideloaded apps (SideStore, AltStore, LiveContainer) because no server is involved.
enum Notifications {
    private static var asked = false

    static func requestIfNeeded() {
        guard !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func reschedule(for data: AppData?) {
        guard let data else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix("shuru.") }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            var requests: [UNNotificationRequest] = []
            let s = data.settings

            // Hour check-ins
            if s.hours && s.checkEvery > 0 && s.chime != .off {
                var h = s.wakeHour + s.checkEvery
                while h <= min(s.bedHour, 23) {
                    let content = UNMutableNotificationContent()
                    content.title = "It’s " + Day.hourLabel(h)
                    content.body = "What did the last " + (s.checkEvery == 1 ? "hour" : "\(s.checkEvery) hours") + " go to?"
                    content.sound = s.chime == .sound ? .default : nil
                    content.interruptionLevel = .active
                    var dc = DateComponents()
                    dc.hour = h
                    dc.minute = 0
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                    requests.append(UNNotificationRequest(identifier: "shuru.checkin.\(h)", content: content, trigger: trigger))
                    h += s.checkEvery
                }
            }

            // Timed routines
            if s.remindRoutines {
                for r in data.routines where r.enabled && r.trigger.kind == .time {
                    let days = r.days.isEmpty ? Set(1...7) : r.days
                    for wd in days.sorted() {
                        let content = UNMutableNotificationContent()
                        content.title = r.trigger.label
                        content.body = r.steps.count > 1 ? r.title + " → then \(r.steps.count - 1) more" : r.title
                        content.sound = .default
                        var dc = DateComponents()
                        dc.weekday = wd
                        dc.hour = r.trigger.hour
                        dc.minute = r.trigger.minute
                        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                        requests.append(UNNotificationRequest(identifier: "shuru.routine.\(r.id.uuidString).\(wd)", content: content, trigger: trigger))
                    }
                }

                // Timed one-off tasks in the next week
                let now = Date()
                for t in data.tasks where t.timeHour != nil && !t.isRepeating && !t.isDone(on: t.date) {
                    var dc = Day.calendar.dateComponents([.year, .month, .day], from: Day.date(t.date))
                    dc.hour = t.timeHour
                    dc.minute = t.timeMinute
                    guard let fire = Day.calendar.date(from: dc), fire > now, fire < now.addingTimeInterval(8 * 86400) else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = t.timeLabel ?? "Now"
                    content.body = t.title
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                    requests.append(UNNotificationRequest(identifier: "shuru.task.\(t.id.uuidString)", content: content, trigger: trigger))
                }
            }

            // iOS keeps at most 64 pending notifications per app.
            for r in requests.prefix(60) { center.add(r) }
        }
    }
}
