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

    /// Shows a notification right away (used when you arrive somewhere).
    static func announce(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: "shuru.arrive.\(id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// "Your 15 min of YouTube is up."
    static func unlockEnds(key: String, name: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Time’s up on " + name
        content.body = "That’s the time you bought. Close it, or spend another token next time you open it."
        content.sound = .default
        let seconds = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["shuru.unlock.\(key)"])
        center.add(UNNotificationRequest(identifier: "shuru.unlock.\(key)", content: content, trigger: trigger))
    }

    /// For the step that's now first on Now: a quiet note at its minimum, an alert at its maximum.
    static func scheduleLimits(for step: Step, title: String, from start: Date) {
        cancelLimits()
        let center = UNUserNotificationCenter.current()
        if let mn = step.minMinutes {
            let content = UNMutableNotificationContent()
            content.title = Step.duration(mn) + " in"
            content.body = "You can stop “" + title + "” here if you want, or keep going."
            content.interruptionLevel = .passive
            let at = start.addingTimeInterval(TimeInterval(mn * 60)).timeIntervalSinceNow
            if at > 1 {
                center.add(UNNotificationRequest(identifier: "shuru.limit.min", content: content,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: at, repeats: false)))
            }
        }
        if let mx = step.maxMinutes {
            let content = UNMutableNotificationContent()
            content.title = "Time’s up"
            content.body = "You said you’d stop “" + title + "” by " + Step.duration(mx) + "."
            content.sound = .default
            content.interruptionLevel = .active
            let at = start.addingTimeInterval(TimeInterval(mx * 60)).timeIntervalSinceNow
            if at > 1 {
                center.add(UNNotificationRequest(identifier: "shuru.limit.max", content: content,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: at, repeats: false)))
            }
        }
    }

    static func cancelLimits() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["shuru.limit.min", "shuru.limit.max"])
    }

    static func breakEnds(at date: Date, next: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Break’s over"
        content.body = next.map { "Next up: " + $0 } ?? "Back to it when you’re ready."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["shuru.break"])
        center.add(UNNotificationRequest(identifier: "shuru.break", content: content, trigger: trigger))
    }

    static func cancelBreak() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["shuru.break"])
    }

    static func cancelUnlock(key: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["shuru.unlock.\(key)"])
    }

    static func reschedule(for data: AppData?) {
        guard let data else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter {
                $0.hasPrefix("shuru.checkin.") || $0.hasPrefix("shuru.routine.") || $0.hasPrefix("shuru.task.")
                    || $0 == "shuru.review" || $0 == "shuru.monthreview"
            }
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
                        content.title = r.hasName ? r.title : r.trigger.label
                        let first = r.steps.first?.title ?? r.title
                        content.body = r.steps.count > 1 ? first + " → then \(r.steps.count - 1) more" : first
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

            // Weekly review, on the last day of your week
            if s.reviewReminder {
                let content = UNMutableNotificationContent()
                content.title = "Weekly review"
                content.body = "5 minutes to look back and pick what matters next week."
                content.sound = .default
                var dc = DateComponents()
                dc.weekday = s.weekStartsMonday ? 1 : 7
                dc.hour = 19
                dc.minute = 0
                requests.insert(UNNotificationRequest(identifier: "shuru.review", content: content,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)), at: 0)
            }

            // Month review, on the last evening of a month that has goals
            let month = Day.monthKey(Day.today)
            if s.reviewReminder && data.goals.contains(where: { $0.month == month }) {
                var dc = Day.calendar.dateComponents([.year, .month], from: Day.date(month + "-01"))
                dc.day = Day.daysIn(month: month)
                dc.hour = 19
                dc.minute = 30
                if let fire = Day.calendar.date(from: dc), fire > Date() {
                    let content = UNMutableNotificationContent()
                    content.title = Day.monthName(month) + " in review"
                    content.body = "See what moved toward your goals, and keep any of them going."
                    content.sound = .default
                    content.userInfo = ["month": month]
                    requests.insert(UNNotificationRequest(identifier: "shuru.monthreview", content: content,
                                                          trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)), at: 0)
                }
            }

            // iOS keeps at most 64 pending notifications per app.
            for r in requests.prefix(60) { center.add(r) }
        }
    }
}
