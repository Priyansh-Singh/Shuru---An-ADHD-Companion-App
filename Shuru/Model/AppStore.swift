import Foundation
import SwiftUI
import Combine
import UIKit

enum Page: String, CaseIterable, Identifiable {
    case settings, dump, hours, now, calendar, routines, week
    var id: String { rawValue }

    var label: String {
        switch self {
        case .settings: return "Settings"
        case .dump: return "Brain dump"
        case .hours: return "Hours"
        case .now: return "Now"
        case .calendar: return "Calendar"
        case .routines: return "Routines"
        case .week: return "This week"
        }
    }
}

enum PauseStage: String, Equatable {
    case breath, past, future, say, decide
}

enum BreathPhase: Equatable {
    case inhale, exhale
}

/// One thing the Now screen can show: a step of a task or routine, for a day.
struct NowItem: Identifiable, Equatable {
    enum Kind: Equatable { case task, routine }
    let kind: Kind
    let refID: UUID
    let day: String
    let stepIndex: Int
    let stepCount: Int
    let step: Step
    let triggerLabel: String
    let rolledFrom: String?

    var baseKey: String { (kind == .task ? "t:" : "r:") + refID.uuidString + "@" + day }
    var id: String { baseKey + "#" + String(stepIndex) }
    var isChain: Bool { stepCount > 1 }
}

/// Everything done on one task or routine in a day, counted as one.
struct DoneRun: Identifiable {
    let id: String
    let refID: UUID?
    let isRoutine: Bool
    let title: String
    let typeID: String
    let day: String
    let at: Date
    let stepsDone: Int
    let stepCount: Int?
    let finished: Bool
    let earnedToken: Bool
    let goalID: UUID?
    let seconds: Int

    /// "4 steps" when finished, "2 of 4 steps" when not, nil for a single step.
    var stepsText: String? {
        let total = max(stepCount ?? stepsDone, stepsDone)
        if finished { return total > 1 ? "\(total) steps" : nil }
        return "\(stepsDone) of \(total) steps"
    }
}

struct SkippedThing: Identifiable {
    let key: String
    let title: String
    let isRoutine: Bool
    var id: String { key }
}

struct CompletionResult {
    let label: String
    let whole: Bool
}

struct RunningTimer: Equatable {
    let itemID: String
    let start: Date
    let end: Date
}

final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var data: AppData {
        didSet {
            Day.startHour = data.settings.dayStartHour
            scheduleSave()
        }
    }

    // Things that are not saved
    @Published var page: Page = .now
    @Published var pauseStage: PauseStage? = nil
    @Published var breathPhase: BreathPhase? = nil
    @Published var timer: RunningTimer? = nil
    /// True while the Coming up / Done panel is open on Now (hides the page dots).
    @Published var nowPanelOpen = false
    /// The app you were opening when the pause showed up.
    @Published var pauseApp: GuardedAppInfo? = nil
    /// A short message shown at the top of Now.
    @Published var banner: String? = nil
    /// The month review to show, if one was asked for (from Calendar, This week or a notification).
    @Published var monthReview: MonthReviewRequest? = nil
    private var lastBounce: [String: Date] = [:]
    /// Which way the current swipe went (set by the pager, read by Now). Not published on purpose.
    var swipeAxis: SwipeAxis? = nil
    @Published var activeLog: (itemID: String, startHour: Int)? = nil

    private var saveWork: DispatchWorkItem?
    private let fileURL: URL

    var settings: AppSettings { data.settings }

    /// First day of the current week, following the Monday/Sunday setting.
    func weekStart(of key: String = Day.today) -> String {
        Day.weekStart(of: key, mondayFirst: data.settings.weekStartsMonday)
    }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shuru.json")
        fileURL = url
        data = AppStore.load(from: url)
        Day.startHour = data.settings.dayStartHour
        if !data.seeded {
            seedExamples()
            saveNow()
        }
        normalizeTokens()
    }

    // MARK: Saving

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Loads saved data. Missing keys (added in later versions) fall back to defaults.
    private static func load(from url: URL) -> AppData {
        guard let raw = try? Data(contentsOf: url) else { return AppData() }
        return decode(raw) ?? AppData()
    }

    /// Reads saved data, filling in anything added in later versions with defaults.
    static func decode(_ raw: Data) -> AppData? {
        if let direct = try? decoder().decode(AppData.self, from: raw) { return direct }
        guard
            let defaultsData = try? encoder().encode(AppData()),
            let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any],
            let saved = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
            saved["settings"] != nil || saved["tasks"] != nil || saved["routines"] != nil
        else { return nil }
        let merged = merge(defaults, saved)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? decoder().decode(AppData.self, from: mergedData)
    }

    /// Everything, as the JSON that goes into a backup.
    func exportData() -> Data? {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try? e.encode(data)
    }

    /// Replaces everything with a backup. Returns false if the file isn't a Shuru backup.
    func importData(_ raw: Data) -> Bool {
        guard let restored = AppStore.decode(raw) else { return false }
        data = restored
        timer = nil
        activeLog = nil
        endPause()
        saveNow()
        return true
    }

    private static func merge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let b = base[k] as? [String: Any], let o = v as? [String: Any], k == "settings" {
                out[k] = merge(b, o)
            } else {
                out[k] = v
            }
        }
        return out
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
            Notifications.reschedule(for: self?.data)
            if let d = self?.data { Places.shared.sync(routines: d.settings.useLocation ? d.routines : []) }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        guard let encoded = try? AppStore.encoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: [.atomic])
    }

    // MARK: Lifecycle and links

    func becameActive() {
        normalizeTokens()
        if let b = data.breakUntil, Date().timeIntervalSince(b) > 2 * 3600 { data.breakUntil = nil }
        let cutoff = Day.add(-14, to: Day.today)
        if data.skipped.contains(where: { String($0.split(separator: "@").last ?? "") < cutoff }) {
            data.skipped = data.skipped.filter { String($0.split(separator: "@").last ?? "") >= cutoff }
        }
        if data.snoozed.values.contains(where: { Date().timeIntervalSince($0) > 86400 }) {
            data.snoozed = data.snoozed.filter { Date().timeIntervalSince($0.value) <= 86400 }
        }
        let today = "@" + Day.today
        if data.primed.contains(where: { !$0.contains(today) }) {
            data.primed = data.primed.filter { $0.contains(today) }
        }
        Notifications.requestIfNeeded()
        Notifications.reschedule(for: data)
        Places.shared.sync(routines: data.settings.useLocation ? data.routines : [])
        if let t = timer, Date() > t.end.addingTimeInterval(3600) { timer = nil }
    }

    func handle(url: URL) {
        guard url.scheme == "shuru" else { return }
        switch url.host ?? "" {
        case "pause":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            requestPause(appInput: items.first(where: { $0.name == "app" })?.value)
        case "start":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let raw = items.first(where: { $0.name == "routine" })?.value, let id = UUID(uuidString: raw) {
                cueHappened(routineID: id, announce: false, automatic: true)
            }
            go(to: .now)
        case "hours": go(to: .hours)
        case "calendar": go(to: .calendar)
        case "dump": go(to: .dump)
        default: go(to: .now)
        }
    }

    func go(to page: Page) {
        if visiblePages.contains(page) { self.page = page } else { self.page = .now }
    }

    var visiblePages: [Page] {
        Page.allCases.filter { p in
            switch p {
            case .dump: return data.settings.brainDump
            case .hours: return data.settings.hours
            default: return true
            }
        }
    }

    // MARK: Pause before scrolling

    /// True when the pause is the "before you start" one for a task, not one for an app.
    @Published var pauseForTask = false

    // MARK: Breaks after tasks

    /// Showing "Take a break?" on Now.
    @Published var askBreak = false

    var longBreakMinutes: Int {
        switch data.settings.breakMinutes {
        case 10: return 20
        case 15: return 30
        default: return 15
        }
    }

    func startBreak(minutes: Int) {
        askBreak = false
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        data.breakUntil = until
        let next = queue().first.map { displayTitle($0) }
        Notifications.breakEnds(at: until, next: next)
        if data.settings.hours && data.settings.autoLog {
            let h = Day.hour(of: Date())
            var dayLog = data.hours[Day.today] ?? [:]
            if dayLog[String(h)] == nil {
                dayLog[String(h)] = HourEntry(typeID: "rest", note: "Break", auto: true)
                data.hours[Day.today] = dayLog
            }
        }
    }

    func skipBreak() {
        askBreak = false
    }

    func endBreak() {
        data.breakUntil = nil
        Notifications.cancelBreak()
    }

    var taskPauseStages: [PauseStage] {
        let s = data.settings
        var stages: [PauseStage] = []
        if s.taskPauseBreath { stages.append(.breath) }
        if s.taskPausePast { stages.append(.past) }
        if s.taskPauseFuture { stages.append(.future) }
        return stages
    }

    /// Runs once per task per day, when it becomes the next thing on Now.
    func startTaskPause(for item: NowItem) {
        guard data.settings.taskPause, pauseStage == nil, !data.primed.contains(item.id) else { return }
        let stages = taskPauseStages
        data.primed.insert(item.id)
        guard let first = stages.first else { return }
        pauseApp = nil
        pauseForTask = true
        breathPhase = nil
        pauseStage = first
    }

    func isLastPauseStage(_ stage: PauseStage) -> Bool {
        let stages = pauseForTask ? taskPauseStages : pauseStages
        return stages.last == stage
    }

    var pauseStages: [PauseStage] {
        let s = data.settings
        var stages: [PauseStage] = []
        if s.pauseBreath { stages.append(.breath) }
        if s.pausePast { stages.append(.past) }
        if s.pauseFuture { stages.append(.future) }
        if s.pauseSay { stages.append(.say) }
        if stages.last != .say { stages.append(.decide) }
        return stages
    }

    func unlockedUntil(_ key: String) -> Date? {
        guard let d = data.unlocks[key], d > Date() else { return nil }
        return d
    }

    private func isUnlocked(_ app: GuardedAppInfo) -> Bool {
        if unlockedUntil(app.key) != nil { return true }
        if app.key == GuardedAppInfo.anyApp.key, let until = data.pauseCooldownUntil, until > Date() { return true }
        return false
    }

    private func noteSeen(_ app: GuardedAppInfo) {
        guard app.key != GuardedAppInfo.anyApp.key else { return }
        data.seenApps[app.key] = SeenApp(name: app.name, lastSeen: Date())
    }

    /// For the "Check before opening" Shortcuts action: true means show the pause.
    /// Because this action doesn't open Shuru by itself, going back to an unlocked app never loops.
    func shouldPause(appInput: String?) -> Bool {
        let app = GuardedAppInfo.match(appInput)
        noteSeen(app)
        guard data.settings.pause else { return false }
        return !isUnlocked(app)
    }

    func requestPause(appInput: String? = nil) {
        let app = GuardedAppInfo.match(appInput)
        noteSeen(app)
        guard data.settings.pause else { go(to: .now); return }
        if isUnlocked(app) {
            // One-action setups open Shuru every time. Send them back, but never ping-pong.
            if let last = lastBounce[app.key], Date().timeIntervalSince(last) < 8 {
                banner = app.key == GuardedAppInfo.anyApp.key
                    ? "It’s unlocked. Open it from your home screen."
                    : "\(app.name) is unlocked. Open it from your home screen."
                go(to: .now)
                return
            }
            lastBounce[app.key] = Date()
            openApp(app)
            return
        }
        pauseApp = app
        pauseForTask = false
        page = .now
        breathPhase = nil
        pauseStage = pauseStages.first
    }

    var quickLooksLeft: Int {
        let used = (data.quickLooks?.day == Day.today) ? (data.quickLooks?.count ?? 0) : 0
        return max(0, data.settings.quickLooksPerDay - used)
    }

    /// Spends tokens on time in the app you were opening.
    @discardableResult
    func buyTime(tokens n: Int) -> Bool {
        normalizeTokens()
        guard data.settings.tokens, n > 0, data.tokens >= n else { return false }
        data.tokens -= n
        unlock(pauseApp ?? GuardedAppInfo.anyApp, minutes: n * data.settings.minutesPerToken)
        return true
    }

    func quickLook() {
        guard quickLooksLeft > 0 else { return }
        let used = (data.quickLooks?.day == Day.today) ? (data.quickLooks?.count ?? 0) : 0
        data.quickLooks = TokenDay(day: Day.today, count: used + 1)
        unlock(pauseApp ?? GuardedAppInfo.anyApp, minutes: 2)
    }

    /// Used when tokens are switched off: a free pass for the snooze length.
    func backFree() {
        unlock(pauseApp ?? GuardedAppInfo.anyApp, minutes: data.settings.snoozeMinutes)
    }

    private func unlock(_ app: GuardedAppInfo, minutes: Int) {
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        data.unlocks[app.key] = until
        if app.key == GuardedAppInfo.anyApp.key { data.pauseCooldownUntil = until }
        Notifications.unlockEnds(key: app.key, name: app.name, at: until)
        endPause()
        lastBounce[app.key] = Date()
        if app.returnURL != nil {
            openApp(app)
        } else {
            banner = "Unlocked for \(minutes) min. Open " + app.name + " from your home screen."
        }
    }

    func lockNow(_ key: String) {
        data.unlocks[key] = nil
        if key == GuardedAppInfo.anyApp.key { data.pauseCooldownUntil = nil }
        Notifications.cancelUnlock(key: key)
    }

    func forgetApp(_ key: String) {
        data.seenApps[key] = nil
        lockNow(key)
    }

    func openApp(_ app: GuardedAppInfo) {
        guard let s = app.returnURL, let url = URL(string: s) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func advancePause() {
        guard let current = pauseStage else { return }
        let stages = pauseForTask ? taskPauseStages : pauseStages
        if let i = stages.firstIndex(of: current), i + 1 < stages.count {
            pauseStage = stages[i + 1]
        } else if pauseForTask {
            endPause()
            return
        } else {
            pauseStage = .decide
        }
        breathPhase = nil
    }

    func endPause() {
        pauseStage = nil
        breathPhase = nil
        pauseApp = nil
        pauseForTask = false
    }

    // MARK: Types

    func type(_ id: String) -> TaskType { data.type(id) }

    func addType(name: String, colorHex: String) -> TaskType {
        let base = name.lowercased().filter { $0.isLetter || $0.isNumber }
        var id = base.isEmpty ? "type" : base
        var n = 2
        while data.types.contains(where: { $0.id == id }) { id = base + String(n); n += 1 }
        let t = TaskType(id: id, name: name, colorHex: colorHex)
        data.types.append(t)
        return t
    }

    // MARK: What is on a day

    func tasks(on day: String, includeRollover: Bool = true) -> [PlannedTask] {
        let today = Day.today
        return data.tasks.filter { t in
            if t.scheduled(on: day) { return true }
            if includeRollover, day == today, !t.isRepeating, t.date < today, !t.isDone(on: day) { return true }
            return false
        }
    }

    func routines(on day: String) -> [Routine] {
        data.routines.filter { $0.enabled && $0.runs(on: day) }
            .sorted { a, b in
                let ak = a.trigger.kind == .time ? a.trigger.minutesOfDay : 10_000
                let bk = b.trigger.kind == .time ? b.trigger.minutesOfDay : 10_000
                return ak < bk
            }
    }

    func progress(routine: Routine, day: String) -> Int {
        data.progress["r:" + routine.id.uuidString + "@" + day] ?? 0
    }

    func completions(on day: String) -> [Completion] {
        data.completions.filter { $0.day == day }.sorted { $0.at < $1.at }
    }

    /// The ordered list of things to do today. The first one is shown on Now.
    /// What's due now, in order: timed things whose time has come, then untimed ones.
    /// Anything scheduled for later today waits in `laterToday()` until its time.
    func queue(day: String = Day.today) -> [NowItem] { plan(day: day).due }

    /// Timed tasks and routines whose time hasn't come yet today, soonest first.
    func laterToday(day: String = Day.today) -> [NowItem] { plan(day: day).later }

    /// "6 pm" for something scheduled at a time.
    func startsAt(_ item: NowItem) -> String? {
        if let s = snoozedUntil(item) { return Day.clock(s) }
        if item.kind == .routine, let r = data.routines.first(where: { $0.id == item.refID }), r.trigger.kind == .time {
            return Day.clock(hour: r.trigger.hour, minute: r.trigger.minute)
        }
        if item.kind == .task, let t = data.tasks.first(where: { $0.id == item.refID }), let h = t.timeHour {
            return Day.clock(hour: h, minute: t.timeMinute)
        }
        return nil
    }

    /// Minutes into the day for a clock time. Before the new-day hour counts as late night (1 am is 25:00).
    private func dayMinutes(hour: Int, minute: Int) -> Int {
        (hour < Day.startHour ? hour + 24 : hour) * 60 + minute
    }

    private func plan(day: String) -> (due: [NowItem], later: [NowItem]) {
        let nowMinutes = Day.hour(of: Date()) * 60 + Day.calendar.component(.minute, from: Date())
        // A day other than today: nothing is "later", it's all just the plan.
        let isToday = day == Day.today
        let now = Date()
        /// A snooze for this item today: still waiting (later), or just ended (back in line at that time).
        func snoozeState(_ base: String) -> (later: Bool, minutes: Int)? {
            guard isToday, let until = data.snoozed[base] else { return nil }
            return (until > now, Day.hour(of: until) * 60 + Day.calendar.component(.minute, from: until))
        }
        var entries: [(item: NowItem, bucket: Int, minutes: Int, order: Int)] = []
        var order = 0

        for r in data.routines where r.enabled && r.runs(on: day) && !r.steps.isEmpty {
            let base = "r:" + r.id.uuidString + "@" + day
            let idx = data.progress[base] ?? 0
            guard idx < r.steps.count else { continue }
            let item = NowItem(kind: .routine, refID: r.id, day: day, stepIndex: idx, stepCount: r.steps.count,
                               step: r.steps[idx], triggerLabel: r.hasName ? r.title : r.trigger.label, rolledFrom: nil)
            if data.skipped.contains(base) { continue }
            // A cue routine waits for its cue: arriving somewhere, a Start tap, or a Shortcut.
            if r.trigger.isCue && data.started[base] == nil { continue }
            if let s = snoozeState(base) {
                entries.append((item, s.later ? 2 : 0, s.minutes, order))
            } else if r.trigger.isCue, let at = data.started[base] {
                let c = Day.calendar.dateComponents([.hour, .minute], from: at)
                entries.append((item, 0, (c.hour ?? 0) * 60 + (c.minute ?? 0), order))
            } else {
                let at = dayMinutes(hour: r.trigger.hour, minute: r.trigger.minute)
                entries.append((item, isToday && at > nowMinutes ? 2 : 0, at, order))
            }
            order += 1
        }

        for t in tasks(on: day) where !t.isDone(on: day) && !t.steps.isEmpty {
            let base = "t:" + t.id.uuidString + "@" + day
            let idx = data.progress[base] ?? 0
            guard idx < t.steps.count, !data.skipped.contains(base) else { continue }
            let rolled = (!t.isRepeating && t.date < day) ? t.date : nil
            var label = t.timeLabel ?? "Today"
            if let rolled { label = "From " + Day.shortWeekdays[Day.weekday(rolled) - 1] }
            let item = NowItem(kind: .task, refID: t.id, day: day, stepIndex: idx, stepCount: t.steps.count,
                               step: t.steps[idx], triggerLabel: label, rolledFrom: rolled)
            let minutes = t.timeHour.map { dayMinutes(hour: $0, minute: t.timeMinute) }
            // Rolled over from an earlier day: it's overdue, whatever time it had.
            let bucket: Int
            if let minutes, rolled == nil { bucket = isToday && minutes > nowMinutes ? 2 : 0 } else { bucket = minutes == nil ? 1 : 0 }
            if let s = snoozeState(base) {
                entries.append((item, s.later ? 2 : 0, s.minutes, order))
            } else {
                entries.append((item, bucket, minutes ?? 0, order))
            }
            order += 1
        }

        entries.sort { a, b in
            if a.bucket != b.bucket { return a.bucket < b.bucket }
            if a.minutes != b.minutes { return a.minutes < b.minutes }
            return a.order < b.order
        }
        let later = entries.filter { $0.bucket == 2 }.map(\.item)
        var items = entries.filter { $0.bucket != 2 }.map(\.item)

        let pushed = data.notNow[day] ?? []
        if !pushed.isEmpty {
            let keep = items.filter { !pushed.contains($0.baseKey) }
            let moved = pushed.compactMap { key in items.first { $0.baseKey == key } }
            items = keep + moved
        }
        if let pin = data.pinned[day], let i = items.firstIndex(where: { $0.baseKey == pin }) {
            let it = items.remove(at: i)
            items.insert(it, at: 0)
        }
        return (items, later)
    }

    func isSmaller(_ item: NowItem) -> Bool { data.smaller.contains(item.id) }

    func displayTitle(_ item: NowItem) -> String {
        isSmaller(item) ? item.step.smallerOrDefault : item.step.title
    }

    // MARK: Doing things

    @discardableResult
    func complete(_ item: NowItem) -> CompletionResult {
        let base = item.baseKey
        let next = item.stepIndex + 1
        let whole = next >= item.stepCount
        data.progress[base] = next

        if item.kind == .task, whole, let i = data.tasks.firstIndex(where: { $0.id == item.refID }) {
            if data.tasks[i].isRepeating {
                data.tasks[i].doneDays.insert(item.day)
            } else {
                data.tasks[i].doneDays.insert(data.tasks[i].date)
            }
        }

        let earned = whole ? earnToken() : false
        var record = Completion(title: item.step.title, typeID: item.step.typeID, at: Date(), refID: item.refID,
                                isRoutine: item.kind == .routine, stepIndex: item.stepIndex,
                                finishedWhole: whole, earnedToken: earned)
        record.goalID = recordGoal(tagged: item.kind == .task
            ? data.tasks.first(where: { $0.id == item.refID })?.goalID
            : data.routines.first(where: { $0.id == item.refID })?.goalID, day: Day.today)
        if let start = data.startedAt[item.id] {
            record.seconds = max(0, Int(Date().timeIntervalSince(start)))
            record.limitMin = item.step.minMinutes
            record.limitMax = item.step.maxMinutes
        }
        data.completions.append(record)
        data.startedAt[item.id] = nil
        Notifications.cancelLimits()
        if whole {
            data.notNow[item.day]?.removeAll { $0 == base }
            if data.pinned[item.day] == base { data.pinned[item.day] = nil }
            if data.snoozed.removeValue(forKey: base) != nil { Notifications.cancelSnooze(key: base) }
        }
        if data.settings.hours && data.settings.autoLog {
            autoLog(typeID: item.step.typeID, note: item.step.title, itemID: item.id)
        }
        if timer?.itemID == item.id { timer = nil }
        activeLog = nil

        var parts: [String] = []
        if item.isChain && !whole {
            parts.append("Step \(item.stepIndex + 1) of \(item.stepCount) done")
        } else if item.kind == .routine && whole {
            parts.append("Routine done")
        }
        if data.settings.tokens && whole {
            parts.append(earned ? "+1 token" : "Daily limit reached")
        }
        return CompletionResult(label: parts.joined(separator: " · "), whole: whole)
    }

    func toggleSmaller(_ item: NowItem) {
        if data.smaller.contains(item.id) { data.smaller.remove(item.id) } else { data.smaller.insert(item.id) }
    }

    func notNow(_ item: NowItem) {
        var list = data.notNow[item.day] ?? []
        list.removeAll { $0 == item.baseKey }
        list.append(item.baseKey)
        data.notNow[item.day] = list
        if data.pinned[item.day] == item.baseKey { data.pinned[item.day] = nil }
        data.pushes[item.refID.uuidString, default: 0] += 1
        if timer?.itemID == item.id { timer = nil }
        data.startedAt[item.id] = nil
        Notifications.cancelLimits()
    }

    // MARK: Later and skip

    /// Takes it off Now until a time; it waits in Coming up and comes back on its own.
    func snooze(_ item: NowItem, until: Date) {
        let key = item.baseKey
        data.snoozed[key] = until
        data.notNow[item.day]?.removeAll { $0 == key }
        if data.pinned[item.day] == key { data.pinned[item.day] = nil }
        if timer?.itemID == item.id { stopTimer() }
        Notifications.snoozeEnds(key: key, at: until, title: displayTitle(item))
        banner = "Back at " + Day.clock(until)
    }

    /// Missed it, or not today. Not counted as done; one-off tasks come back tomorrow.
    func skipToday(_ item: NowItem) {
        let key = item.baseKey
        data.skipped.insert(key)
        data.snoozed[key] = nil
        data.notNow[item.day]?.removeAll { $0 == key }
        if data.pinned[item.day] == key { data.pinned[item.day] = nil }
        if timer?.itemID == item.id { stopTimer() }
        Notifications.cancelSnooze(key: key)
        banner = "Skipped for today"
    }

    /// Undoes a snooze or a skip: straight back in line.
    func bringBack(_ key: String) {
        data.snoozed[key] = nil
        data.skipped.remove(key)
        Notifications.cancelSnooze(key: key)
    }

    func snoozedUntil(_ item: NowItem) -> Date? {
        guard let until = data.snoozed[item.baseKey], until > Date() else { return nil }
        return until
    }

    func isSkipped(task: PlannedTask, on day: String) -> Bool {
        data.skipped.contains("t:" + task.id.uuidString + "@" + day)
    }

    func skippedToday() -> [SkippedThing] {
        let suffix = "@" + Day.today
        return data.skipped.filter { $0.hasSuffix(suffix) }.sorted().compactMap { key in
            let id = UUID(uuidString: String(key.dropFirst(2).prefix(36)))
            if key.hasPrefix("r:"), let r = data.routines.first(where: { $0.id == id }) {
                return SkippedThing(key: key, title: r.title, isRoutine: true)
            }
            if key.hasPrefix("t:"), let t = data.tasks.first(where: { $0.id == id }) {
                return SkippedThing(key: key, title: t.title, isRoutine: false)
            }
            return nil
        }
    }

    // MARK: Done, grouped

    /// Steps of the same task or routine on the same day, counted as one.
    func runs(_ completions: [Completion]) -> [DoneRun] {
        var order: [String] = []
        var groups: [String: [Completion]] = [:]
        for c in completions.sorted(by: { $0.at < $1.at }) {
            let key = (c.refID?.uuidString ?? c.id.uuidString) + "@" + c.day
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(c)
        }
        return order.compactMap { key -> DoneRun? in
            guard let cs = groups[key], let first = cs.first, let last = cs.last else { return nil }
            let routine = first.isRoutine ? data.routines.first(where: { $0.id == first.refID }) : nil
            let task = first.isRoutine ? nil : data.tasks.first(where: { $0.id == first.refID })
            return DoneRun(id: key, refID: first.refID, isRoutine: first.isRoutine,
                           title: routine?.title ?? task?.title ?? first.title,
                           typeID: task?.typeID ?? first.typeID, day: first.day, at: last.at,
                           stepsDone: cs.count, stepCount: routine?.steps.count ?? task?.steps.count,
                           finished: cs.contains { $0.finishedWhole },
                           earnedToken: cs.contains { $0.earnedToken },
                           goalID: cs.compactMap(\.goalID).first,
                           seconds: cs.compactMap(\.seconds).reduce(0, +))
        }
    }

    func runs(on day: String) -> [DoneRun] { runs(completions(on: day)) }

    func pushes(_ item: NowItem) -> Int { data.pushes[item.refID.uuidString] ?? 0 }

    func pickOne(excluding item: NowItem?) {
        let q = queue()
        let pool = q.filter { $0.baseKey != item?.baseKey }
        guard let pick = pool.randomElement() else { return }
        data.pinned[Day.today] = pick.baseKey
        data.notNow[Day.today]?.removeAll { $0 == pick.baseKey }
    }

    func startTimer(for item: NowItem, minutes: Int = 5) {
        let now = Date()
        timer = RunningTimer(itemID: item.id, start: now, end: now.addingTimeInterval(TimeInterval(minutes * 60)))
        beginLogging(item)
    }

    func stopTimer() { timer = nil }

    func beginLogging(_ item: NowItem) {
        guard data.settings.hours && data.settings.autoLog else { return }
        let h = Day.hour(of: Date())
        activeLog = (item.id, h)
        let day = Day.today
        var dayLog = data.hours[day] ?? [:]
        if dayLog[String(h)] == nil {
            dayLog[String(h)] = HourEntry(typeID: item.step.typeID, note: item.step.title, auto: true)
            data.hours[day] = dayLog
        }
    }

    private func autoLog(typeID: String, note: String, itemID: String) {
        let day = Day.today
        let to = Day.hour(of: Date())
        let from = (activeLog?.itemID == itemID) ? (activeLog?.startHour ?? to) : to
        var dayLog = data.hours[day] ?? [:]
        for h in min(from, to)...to where dayLog[String(h)] == nil {
            dayLog[String(h)] = HourEntry(typeID: typeID, note: note, auto: true)
        }
        data.hours[day] = dayLog
    }

    // MARK: Tasks (calendar)

    func addTask(title: String, day: String, typeID: String = "other") {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        data.tasks.append(PlannedTask(steps: [Step(title: t, typeID: typeID)], date: day))
    }

    func upsert(task: PlannedTask) {
        if let i = data.tasks.firstIndex(where: { $0.id == task.id }) { data.tasks[i] = task } else { data.tasks.append(task) }
    }

    func delete(task id: UUID) {
        data.tasks.removeAll { $0.id == id }
    }

    /// Ticks a whole task off (or back on) from the calendar.
    func toggleTask(_ task: PlannedTask, day: String) {
        guard let i = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let doneKey = task.isRepeating ? day : task.date
        let base = "t:" + task.id.uuidString + "@" + day
        if data.tasks[i].isDone(on: day) {
            data.tasks[i].doneDays.remove(doneKey)
            data.progress[base] = 0
            if let ci = data.completions.lastIndex(where: { $0.refID == task.id && $0.finishedWhole && $0.day == Day.today }) {
                let c = data.completions.remove(at: ci)
                if c.earnedToken { refundToken() }
            }
        } else {
            data.tasks[i].doneDays.insert(doneKey)
            data.progress[base] = task.steps.count
            let earned = earnToken()
            var record = Completion(title: task.title, typeID: task.typeID, at: Date(), refID: task.id,
                                    isRoutine: false, stepIndex: max(0, task.steps.count - 1),
                                    finishedWhole: true, earnedToken: earned)
            record.goalID = recordGoal(tagged: task.goalID, day: Day.today)
            data.completions.append(record)
        }
    }

    // MARK: Routines

    func upsert(routine: Routine) {
        if let i = data.routines.firstIndex(where: { $0.id == routine.id }) { data.routines[i] = routine } else { data.routines.append(routine) }
    }

    func delete(routine id: UUID) {
        data.routines.removeAll { $0.id == id }
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        if let i = data.routines.firstIndex(where: { $0.id == id }) { data.routines[i].enabled = on }
    }

    // MARK: Time on the current step

    /// Starts timing the step that's now first on Now (once). Only one step is timed at a time.
    func markStarted(_ item: NowItem) {
        guard data.startedAt[item.id] == nil else { return }
        let now = Date()
        data.startedAt = [item.id: now]
        Notifications.scheduleLimits(for: item.step, title: displayTitle(item), from: now)
    }

    func elapsed(_ item: NowItem, at now: Date = Date()) -> TimeInterval? {
        data.startedAt[item.id].map { now.timeIntervalSince($0) }
    }

    // MARK: Tasks that keep rolling over

    static func daysBetween(_ a: String, _ b: String) -> Int {
        Day.calendar.dateComponents([.day], from: Day.date(a), to: Day.date(b)).day ?? 0
    }

    /// The task behind `item` if it has rolled over for 3+ days and we haven't asked about it today.
    func stuckTask(for item: NowItem?) -> PlannedTask? {
        guard let item, item.kind == .task, let from = item.rolledFrom,
              AppStore.daysBetween(from, Day.today) >= 3,
              data.stuckAsked[item.refID.uuidString] != Day.today else { return nil }
        return data.tasks.first { $0.id == item.refID }
    }

    func dismissStuck(_ id: UUID) {
        data.stuckAsked[id.uuidString] = Day.today
    }

    func move(task id: UUID, to day: String) {
        if let i = data.tasks.firstIndex(where: { $0.id == id }) {
            data.tasks[i].date = day
        }
        dismissStuck(id)
    }

    // MARK: Routine streaks

    func doneDays(_ r: Routine) -> Set<String> {
        Set(data.completions.filter { $0.isRoutine && $0.finishedWhole && $0.refID == r.id }.map(\.day))
    }

    /// Scheduled days in a row you finished the routine. Days it doesn't run don't break it,
    /// and today doesn't count against you until it's over.
    func streak(_ r: Routine) -> Int {
        let done = doneDays(r)
        var day = Day.today
        if !done.contains(day) { day = Day.add(-1, to: day) }
        var count = 0
        for _ in 0..<400 {
            if r.runs(on: day) {
                if done.contains(day) { count += 1 } else { break }
            }
            day = Day.add(-1, to: day)
        }
        return count
    }

    /// How many of this week's scheduled days so far you did it.
    func weekProgress(_ r: Routine) -> (done: Int, scheduled: Int) {
        let done = doneDays(r)
        let start = weekStart()
        var d = 0, s = 0
        var day = start
        while day <= Day.today {
            if r.runs(on: day) {
                s += 1
                if done.contains(day) { d += 1 }
            }
            day = Day.add(1, to: day)
        }
        return (d, s)
    }

    // MARK: Monthly goals

    func goals(in month: String) -> [Goal] {
        data.goals.filter { $0.month == month }
    }

    func goal(_ id: UUID?) -> Goal? {
        guard let id else { return nil }
        return data.goals.first { $0.id == id }
    }

    func upsert(goal: Goal) {
        if let i = data.goals.firstIndex(where: { $0.id == goal.id }) { data.goals[i] = goal } else { data.goals.append(goal) }
    }

    func delete(goal id: UUID) {
        data.goals.removeAll { $0.id == id }
        for i in data.tasks.indices where data.tasks[i].goalID == id { data.tasks[i].goalID = nil }
        for i in data.routines.indices where data.routines[i].goalID == id { data.routines[i].goalID = nil }
    }

    /// Steps finished and hours timed toward a goal in its month.
    func progress(_ g: Goal) -> (steps: Int, hours: Double) {
        let done = data.completions.filter { $0.goalID == g.id && Day.monthKey($0.day) == g.month }
        let sessions = runs(done).count
        // Time on Now counts from when a step comes up, so cap each one to keep a forgotten task from inflating it.
        let seconds = done.compactMap(\.seconds).map { Swift.min($0, 3 * 3600) }.reduce(0, +)
        return (sessions, Double(seconds) / 3600)
    }

    /// 0...1 toward the minimum, if there is one.
    func fraction(_ g: Goal) -> Double? {
        guard let min = g.minimum, min > 0 else { return nil }
        let p = progress(g)
        let value = g.unit == .steps ? Double(p.steps) : p.hours
        return Swift.min(1, value / Double(min))
    }

    /// "3 of 8 steps · 1 more to stay on pace", kindly worded.
    func progressText(_ g: Goal) -> String {
        let p = progress(g)
        let have = g.unit == .steps ? "\(p.steps)" : String(format: "%.1f", p.hours)
        guard let min = g.minimum, min > 0 else {
            return g.unit == .steps ? "\(p.steps) session\(p.steps == 1 ? "" : "s") so far" : have + " h so far"
        }
        let unitWord = g.unit == .steps ? (min == 1 ? "session" : "sessions") : "h"
        var text = have + " of \(min) " + unitWord
        let value = g.unit == .steps ? Double(p.steps) : p.hours
        if value >= Double(min) { return text + " · minimum reached" }
        if g.month == Day.monthKey(Day.today) {
            let day = Double(Day.dayNumber(Day.today))
            let pace = Double(min) * day / Double(Day.daysIn(month: g.month))
            let behind = pace - value
            if behind >= 1 {
                let n = Int(behind.rounded(.up))
                text += " · \(n) more " + (g.unit == .steps ? "" : "h ") + "to stay on pace"
            } else {
                text += " · on pace"
            }
        }
        return text
    }

    /// Turns "one step toward the goal" into a normal task on a day you pick.
    func addGoalStep(_ g: Goal, title: String, day: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var task = PlannedTask(steps: [Step(title: t, typeID: "other")], date: day)
        task.goalID = recordGoal(tagged: g.id, day: day)
        data.tasks.append(task)
    }

    /// The goal a finished step counts toward: the tagged goal, or its carried-over twin in that day's month.
    func recordGoal(tagged: UUID?, day: String) -> UUID? {
        guard let tagged, let g = goal(tagged) else { return nil }
        let month = Day.monthKey(day)
        if g.month == month { return g.id }
        if let prev = g.carriedFrom, let p = goal(prev), p.month == month { return p.id }
        if let next = data.goals.first(where: { $0.carriedFrom == g.id && $0.month == month }) { return next.id }
        return g.id
    }

    /// Tags exactly these tasks and routines with a goal (and untags the rest that had it).
    func setTags(goal id: UUID, items: Set<UUID>) {
        for i in data.tasks.indices {
            if items.contains(data.tasks[i].id) { data.tasks[i].goalID = id }
            else if data.tasks[i].goalID == id { data.tasks[i].goalID = nil }
        }
        for i in data.routines.indices {
            if items.contains(data.routines[i].id) { data.routines[i].goalID = id }
            else if data.routines[i].goalID == id { data.routines[i].goalID = nil }
        }
    }

    func isCarried(_ g: Goal) -> Bool { data.goals.contains { $0.carriedFrom == g.id } }

    /// Keeps a goal going into another month. Open tasks and routines tagged with it follow.
    @discardableResult
    func carryOver(_ g: Goal, to month: String) -> Goal? {
        if let existing = data.goals.first(where: { $0.month == month && ($0.carriedFrom == g.id || $0.title == g.title) }) {
            return existing
        }
        guard goals(in: month).count < 3 else { return nil }
        let n = Goal(title: g.title, month: month, minimum: g.minimum, unit: g.unit, carriedFrom: g.id)
        data.goals.append(n)
        for i in data.tasks.indices where data.tasks[i].goalID == g.id {
            let t = data.tasks[i]
            if t.isRepeating || !t.isDone(on: t.date) { data.tasks[i].goalID = n.id }
        }
        for i in data.routines.indices where data.routines[i].goalID == g.id { data.routines[i].goalID = n.id }
        return n
    }

    /// Where carry-overs and "goals for next month" go from a month's review.
    func nextGoalMonth(after month: String) -> String {
        Swift.max(Day.addMonths(1, to: month), Day.monthKey(Day.today))
    }

    /// The last week of a month, when it's time to look back and ahead.
    var monthIsEnding: Bool {
        let today = Day.today
        return Day.dayNumber(today) > Day.daysIn(month: Day.monthKey(today)) - 7
    }

    // MARK: Weekly review

    /// Reviews done near the end of a week plan the next one.
    func reviewTargetWeek() -> String {
        let start = weekStart()
        let pos = AppStore.daysBetween(start, Day.today)
        return pos >= 5 ? Day.add(7, to: start) : start
    }

    /// The focus to show on This week: this week's, or next week's if you've already planned it.
    func currentFocus() -> (week: String, review: WeeklyReview)? {
        let this = weekStart()
        if let r = data.reviews[this], !r.focuses.isEmpty { return (this, r) }
        let next = Day.add(7, to: this)
        if let r = data.reviews[next], !r.focuses.isEmpty { return (next, r) }
        return nil
    }

    /// Saves the review. Earns a token the first time for that week.
    @discardableResult
    func saveReview(focuses: [String]) -> Bool {
        let key = reviewTargetWeek()
        let cleaned = focuses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let first = data.reviews[key] == nil
        data.reviews[key] = WeeklyReview(done: Date(), focuses: cleaned, focusDone: cleaned.map { _ in false })
        return first ? earnToken() : false
    }

    func toggleFocus(week: String, index: Int) {
        guard var r = data.reviews[week], index < r.focuses.count else { return }
        if r.focusDone.count < r.focuses.count { r.focusDone += Array(repeating: false, count: r.focuses.count - r.focusDone.count) }
        r.focusDone[index].toggle()
        data.reviews[week] = r
    }

    /// Once tasks still open from earlier days, plus ones you keep pushing back.
    func slippingTasks() -> [PlannedTask] {
        let today = Day.today
        let open = data.tasks.filter { !$0.isRepeating && !$0.isDone(on: today) }
        let old = open.filter { $0.date < today }
        let pushed = open.filter { $0.date >= today && (data.pushes[$0.id.uuidString] ?? 0) >= 2 }
        return Array((old.sorted { $0.date < $1.date } + pushed).prefix(8))
    }

    // MARK: Cue routines

    func hasStarted(_ r: Routine, day: String = Day.today) -> Bool {
        let base = "r:" + r.id.uuidString + "@" + day
        return data.started[base] != nil || (data.progress[base] ?? 0) > 0
    }

    /// Cue routines running today that haven't started yet (any time of day).
    func cueRoutinesNotStarted(day: String = Day.today) -> [Routine] {
        routines(on: day).filter { $0.trigger.isCue && !hasStarted($0, day: day) && !$0.steps.isEmpty }
    }

    /// Cue routines you could start right now (inside their time window, if they have one).
    func waitingRoutines(day: String = Day.today) -> [Routine] {
        cueRoutinesNotStarted(day: day).filter { $0.trigger.inWindow() }
    }

    /// The cue happened: arrived home, tapped Start, or a Shortcut ran.
    /// Automatic starts (arriving, Shortcuts) are ignored outside the routine's time window; a tap always works.
    func cueHappened(routineID: UUID, announce: Bool, automatic: Bool = false) {
        let day = Day.today
        guard let r = data.routines.first(where: { $0.id == routineID }),
              r.enabled, r.runs(on: day), !r.steps.isEmpty, !hasStarted(r, day: day) else { return }
        if automatic && !r.trigger.inWindow() { return }
        let base = "r:" + r.id.uuidString + "@" + day
        data.started[base] = Date()
        data.notNow[day]?.removeAll { $0 == base }
        if announce {
            Notifications.announce(id: r.id.uuidString, title: r.hasName ? r.title : r.trigger.label,
                                   body: "First: " + r.steps[0].title + (r.steps.count > 1 ? " (1 of \(r.steps.count))" : ""))
        }
    }

    func startLink(for routine: Routine) -> String {
        "shuru://start?routine=" + routine.id.uuidString
    }

    // MARK: Templates

    func upsert(template: Routine) {
        if let i = data.templates.firstIndex(where: { $0.id == template.id }) {
            data.templates[i] = template
        } else {
            data.templates.append(template)
        }
    }

    func delete(template id: UUID) {
        data.templates.removeAll { $0.id == id }
    }

    func hideBuiltInTemplate(_ id: String) {
        data.hiddenTemplates.insert(id)
    }

    func restoreBuiltInTemplates() {
        data.hiddenTemplates = []
    }

    // MARK: Brain dump

    func addThought(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        data.dump.insert(DumpItem(text: t), at: 0)
    }

    func moveThoughtToToday(_ id: UUID) {
        guard let i = data.dump.firstIndex(where: { $0.id == id }) else { return }
        addTask(title: data.dump[i].text, day: Day.today)
        data.dump[i].sortedAt = Date()
    }

    func deleteThought(_ id: UUID) {
        data.dump.removeAll { $0.id == id }
    }

    // MARK: Hours

    func log(hours: [Int], typeID: String, note: String = "") {
        let day = Day.today
        var dayLog = data.hours[day] ?? [:]
        for h in hours { dayLog[String(h)] = HourEntry(typeID: typeID, note: note, auto: false) }
        data.hours[day] = dayLog
        data.lastCheckIn = Date()
    }

    /// Log or change one hour by hand.
    func setHour(_ hour: Int, typeID: String, note: String, day: String = Day.today) {
        var dayLog = data.hours[day] ?? [:]
        dayLog[String(hour)] = HourEntry(typeID: typeID, note: note.trimmingCharacters(in: .whitespacesAndNewlines), auto: false)
        data.hours[day] = dayLog
        if day == Day.today { data.lastCheckIn = Date() }
    }

    func clearHour(_ hour: Int, day: String = Day.today) {
        data.hours[day]?[String(hour)] = nil
    }

    func entry(day: String, hour: Int) -> HourEntry? {
        data.hours[day]?[String(hour)]
    }

    // MARK: Tokens

    /// Clears tokens on Monday when that option is on.
    func normalizeTokens() {
        guard data.settings.tokenWeekly else { return }
        let monday = Day.mondayKey()
        if let w = data.tokensWeek, w != monday {
            data.tokens = 0
        }
        if data.tokensWeek != monday { data.tokensWeek = monday }
    }

    var tokensEarnedToday: Int {
        guard let d = data.tokensDay, d.day == Day.today else { return 0 }
        return d.count
    }

    private func earnToken() -> Bool {
        guard data.settings.tokens else { return false }
        normalizeTokens()
        let cap = data.settings.tokenCap
        let today = tokensEarnedToday
        if cap > 0 && today >= cap { return false }
        data.tokens += 1
        data.tokensDay = TokenDay(day: Day.today, count: today + 1)
        return true
    }

    private func refundToken() {
        data.tokens = max(0, data.tokens - 1)
        let today = tokensEarnedToday
        data.tokensDay = TokenDay(day: Day.today, count: max(0, today - 1))
    }

    func spend(_ reward: Reward) -> Bool {
        normalizeTokens()
        guard data.tokens >= reward.cost else { return false }
        data.tokens -= reward.cost
        return true
    }

    // MARK: Reset

    func resetEverything() {
        let keepSettings = data.settings
        data = AppData()
        data.settings = keepSettings
        seedExamples()
        timer = nil
        activeLog = nil
        endPause()
    }

    private func seedExamples() {
        let today = Day.today
        data.routines = [
            Routine(trigger: Trigger(kind: .place, text: "When I get home"),
                    steps: [
                        Step(title: "Take a bath", smaller: "Just turn on the water", typeID: "care"),
                        Step(title: "Eat dinner", smaller: "Just heat something up", typeID: "care"),
                        Step(title: "Sit down to study", smaller: "Just open your notes", typeID: "study", minMinutes: 2, maxMinutes: 180)
                    ],
                    days: [2, 3, 4, 5, 6], name: "Coming home"),
            Routine(trigger: Trigger(kind: .time, hour: 21, minute: 0),
                    steps: [Step(title: "Put your keys by the door", smaller: "Just find your keys", typeID: "chores")],
                    days: Set(1...7))
        ]
        data.tasks = [
            PlannedTask(steps: [Step(title: "Draft the report intro", smaller: "Write one messy sentence", typeID: "work")], date: today, effort: 3),
            PlannedTask(steps: [Step(title: "Reply to one email", smaller: "Just open your inbox", typeID: "work")], date: today, effort: 1)
        ]
        data.seeded = true
    }
}
