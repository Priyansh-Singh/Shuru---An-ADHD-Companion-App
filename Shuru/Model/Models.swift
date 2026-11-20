import Foundation
import SwiftUI

// MARK: - Types (tags)

struct TaskType: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colorHex: String

    var color: Color { Color(hex: colorHex) }

    static let unknownID = "unknown"

    static let defaults: [TaskType] = [
        TaskType(id: "study", name: "Study", colorHex: "#5B8DEF"),
        TaskType(id: "work", name: "Work", colorHex: "#2FA98C"),
        TaskType(id: "chores", name: "Chores", colorHex: "#D9A13B"),
        TaskType(id: "care", name: "Food & care", colorHex: "#E5794F"),
        TaskType(id: "rest", name: "Rest", colorHex: "#9B7BF0"),
        TaskType(id: "scroll", name: "Scrolling", colorHex: "#E8609A"),
        TaskType(id: "other", name: "Other", colorHex: "#9A948A")
    ]

    static let swatches = ["#5B8DEF", "#2FA98C", "#D9A13B", "#E5794F", "#9B7BF0", "#E8609A", "#3FB6C9", "#8BB33F", "#9A948A"]
}

// MARK: - Steps

struct SubStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var done = false
}

struct Step: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    /// The tiny version used by "Make it smaller", e.g. "Just open your notes".
    var smaller: String = ""
    var typeID: String = "other"
    var minMinutes: Int? = nil
    var maxMinutes: Int? = nil
    var subs: [SubStep] = []

    var smallerOrDefault: String {
        let s = smaller.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return s }
        let first: String = title.prefix(1).lowercased()
        let rest: String = String(title.dropFirst())
        return "Just start: " + first + rest
    }

    var limitText: String? {
        switch (minMinutes, maxMinutes) {
        case let (mn?, mx?): return "At least \(Step.duration(mn)) · stop by \(Step.duration(mx))"
        case let (mn?, nil): return "At least \(Step.duration(mn))"
        case let (nil, mx?): return "Stop by \(Step.duration(mx))"
        default: return nil
        }
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

// MARK: - Triggers

enum TriggerKind: String, Codable, CaseIterable, Identifiable {
    case time, place, after, feeling, app
    var id: String { rawValue }

    var name: String {
        switch self {
        case .time: return "Time"
        case .place: return "Place"
        case .after: return "After"
        case .feeling: return "Feeling"
        case .app: return "App"
        }
    }

    var placeholder: String {
        switch self {
        case .time: return ""
        case .place: return "When I get home"
        case .after: return "After my coffee"
        case .feeling: return "When I feel stuck"
        case .app: return "When I open Instagram"
        }
    }

    var symbol: String {
        switch self {
        case .time: return "clock"
        case .place: return "mappin"
        case .after: return "arrow.turn.down.right"
        case .feeling: return "heart"
        case .app: return "app"
        }
    }
}

struct Trigger: Codable, Hashable {
    var kind: TriggerKind = .time
    var text: String = ""
    var hour: Int = 19
    var minute: Int = 0

    var label: String {
        if kind == .time { return "At " + Day.clock(hour: hour, minute: minute) }
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? kind.placeholder : t
    }

    var minutesOfDay: Int { hour * 60 + minute }
}

// MARK: - Routines and tasks

struct Routine: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger = Trigger()
    var steps: [Step] = []
    /// 1 = Sunday ... 7 = Saturday. Empty means every day.
    var days: Set<Int> = Set(1...7)
    var enabled = true
    var backup: String = ""
    var breatherMinutes: Int = 0

    var title: String { steps.first?.title ?? "Routine" }

    func runs(on day: String) -> Bool {
        days.isEmpty || days.contains(Day.weekday(day))
    }
}

struct PlannedTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var steps: [Step]
    /// The day it is planned for, or the first day of a repeating task.
    var date: String
    /// nil = once. Otherwise the weekdays it repeats on.
    var repeatDays: Set<Int>? = nil
    var timeHour: Int? = nil
    var timeMinute: Int = 0
    /// 1 low, 2 okay, 3 high energy.
    var effort: Int = 2
    var doneDays: Set<String> = []
    var created = Date()

    var title: String { steps.first?.title ?? "Untitled" }
    var typeID: String { steps.first?.typeID ?? "other" }
    var isRepeating: Bool { repeatDays != nil }

    var timeLabel: String? {
        guard let h = timeHour else { return nil }
        return "At " + Day.clock(hour: h, minute: timeMinute)
    }

    /// Whether the task is scheduled on that day (ignoring roll-over).
    func scheduled(on day: String) -> Bool {
        if let days = repeatDays {
            return day >= date && (days.isEmpty || days.contains(Day.weekday(day)))
        }
        return date == day
    }

    func isDone(on day: String) -> Bool {
        if repeatDays != nil { return doneDays.contains(day) }
        return !doneDays.isEmpty
    }
}

// MARK: - History

struct Completion: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var typeID: String
    var at: Date = Date()
    var refID: UUID? = nil
    var isRoutine = false
    var stepIndex = 0
    /// True when this finished the whole task or routine.
    var finishedWhole = true
    var earnedToken = false

    var day: String { Day.key(at) }
}

struct HourEntry: Codable, Hashable {
    var typeID: String
    var note: String = ""
    var auto = false
}

struct DumpItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var created = Date()
    var sortedAt: Date? = nil
}

struct Reward: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    var cost: Int

    static let defaults: [Reward] = [
        Reward(label: "One episode of a show", cost: 5),
        Reward(label: "20 min of guilt-free scrolling", cost: 4),
        Reward(label: "A fancy coffee", cost: 8),
        Reward(label: "An hour of gaming", cost: 10)
    ]
}

struct TokenDay: Codable, Hashable {
    var day: String
    var count: Int
}

// MARK: - Settings

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Palette: String, Codable, CaseIterable, Identifiable {
    case ember, lagoon, dusk
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

enum OrbSpeed: String, Codable, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var factor: Double {
        switch self {
        case .slow: return 0.6
        case .normal: return 1
        case .fast: return 1.7
        }
    }
}

enum OrbEdges: String, Codable, CaseIterable, Identifiable {
    case crisp, soft, hazy
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var blur: CGFloat {
        switch self {
        case .crisp: return 4
        case .soft: return 15
        case .hazy: return 30
        }
    }
}

enum CelebrationStyle: String, Codable, CaseIterable, Identifiable {
    case ripple, sparks, off
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

enum Chime: String, Codable, CaseIterable, Identifiable {
    case sound, silent, off
    var id: String { rawValue }
    var name: String {
        switch self {
        case .sound: return "Sound"
        case .silent: return "Silent"
        case .off: return "Off"
        }
    }
}

struct AppSettings: Codable, Hashable {
    var appearance: Appearance = .dark
    var palette: Palette = .ember
    var orbSpeed: OrbSpeed = .normal
    var orbEdges: OrbEdges = .soft
    var celebration: CelebrationStyle = .ripple

    var holdSeconds: Int = 5
    var showTrigger = true
    var showDots = true
    var haptics = true

    var brainDump = true
    var hours = true
    var pause = true
    var pauseBreath = true
    var pausePast = true
    var pauseFuture = true
    var pauseSay = true
    var snoozeMinutes = 15

    var tokens = true
    var tokenCap = 8
    var tokenWeekly = true

    var wakeHour = 8
    var bedHour = 23
    var checkEvery = 1
    var chime: Chime = .silent
    var autoLog = true
    var remindRoutines = true
}

// MARK: - Everything that is saved

struct AppData: Codable {
    var version = 1
    var seeded = false
    var settings = AppSettings()
    var types: [TaskType] = TaskType.defaults
    var tasks: [PlannedTask] = []
    var routines: [Routine] = []
    var completions: [Completion] = []
    /// day key -> hour (as string) -> entry
    var hours: [String: [String: HourEntry]] = [:]
    var lastCheckIn: Date? = nil
    var dump: [DumpItem] = []
    var rewards: [Reward] = Reward.defaults
    var tokens = 0
    var tokensDay: TokenDay? = nil
    var tokensWeek: String? = nil
    /// "r:<id>@<day>" or "t:<id>@<day>" -> index of the next step
    var progress: [String: Int] = [:]
    /// day -> base keys pushed with "Not now", in order
    var notNow: [String: [String]] = [:]
    /// day -> base key picked with "Pick one for me"
    var pinned: [String: String] = [:]
    /// how many times each task or routine was pushed back, by its id
    var pushes: [String: Int] = [:]
    /// step keys made smaller ("<base>#<step>")
    var smaller: Set<String> = []
    var pauseCooldownUntil: Date? = nil
}

extension AppData {
    func type(_ id: String) -> TaskType {
        if id == TaskType.unknownID { return TaskType(id: id, name: "Don’t remember", colorHex: "#6C6C70") }
        return types.first { $0.id == id } ?? types.first { $0.id == "other" } ?? TaskType(id: "other", name: "Other", colorHex: "#9A948A")
    }
}
