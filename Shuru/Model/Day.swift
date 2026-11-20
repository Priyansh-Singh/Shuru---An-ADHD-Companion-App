import Foundation

/// Days are stored as "yyyy-MM-dd" strings in the user's current calendar.
enum Day {
    static var calendar: Calendar { Calendar.current }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date = Date()) -> String {
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    static func date(_ key: String) -> Date {
        formatter.timeZone = TimeZone.current
        return formatter.date(from: key) ?? calendar.startOfDay(for: Date())
    }

    static var today: String { key(Date()) }

    static func add(_ days: Int, to key: String) -> String {
        let d = calendar.date(byAdding: .day, value: days, to: date(key)) ?? date(key)
        return Day.key(d)
    }

    /// 1 = Sunday ... 7 = Saturday
    static func weekday(_ key: String) -> Int {
        calendar.component(.weekday, from: date(key))
    }

    static func mondayKey(_ date: Date = Date()) -> String {
        let wd = calendar.component(.weekday, from: date)
        let back = (wd + 5) % 7
        let m = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: date)) ?? date
        return key(m)
    }

    static func sundayStart(of key: String) -> String {
        add(-(weekday(key) - 1), to: key)
    }

    static func dayNumber(_ key: String) -> Int {
        calendar.component(.day, from: date(key))
    }

    static let shortWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let longWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let letters = ["S", "M", "T", "W", "T", "F", "S"]
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    static func short(_ key: String) -> String {
        shortWeekdays[weekday(key) - 1] + " " + String(dayNumber(key))
    }

    static func monthYear(_ key: String) -> String {
        let d = date(key)
        let m = calendar.component(.month, from: d)
        let y = calendar.component(.year, from: d)
        return months[m - 1] + " " + String(y)
    }

    static func clock(hour: Int, minute: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "am" : "pm"
        if minute == 0 { return "\(h12) \(ampm)" }
        return String(format: "%d:%02d %@", h12, minute, ampm)
    }

    static func clock(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return clock(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    static func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12) \(h < 12 ? "am" : "pm")"
    }

    static func daysLabel(_ days: Set<Int>) -> String {
        if days.count == 7 || days.isEmpty { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter { days.contains($0) }.map { shortWeekdays[$0 - 1] }.joined(separator: ", ")
    }
}
