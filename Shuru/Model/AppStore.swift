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
        didSet { scheduleSave() }
    }

    // Things that are not saved
    @Published var page: Page = .now
    @Published var pauseStage: PauseStage? = nil
    @Published var breathPhase: BreathPhase? = nil
    @Published var timer: RunningTimer? = nil
    @Published var activeLog: (itemID: String, startHour: Int)? = nil

    private var saveWork: DispatchWorkItem?
    private let fileURL: URL

    var settings: AppSettings { data.settings }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shuru.json")
        fileURL = url
        data = AppStore.load(from: url)
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
        if let direct = try? decoder().decode(AppData.self, from: raw) { return direct }
        guard
            let defaultsData = try? encoder().encode(AppData()),
            let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any],
            let saved = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return AppData() }
        let merged = merge(defaults, saved)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let result = try? decoder().decode(AppData.self, from: mergedData)
        else { return AppData() }
        return result
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
        Notifications.requestIfNeeded()
        Notifications.reschedule(for: data)
        if let t = timer, Date() > t.end.addingTimeInterval(3600) { timer = nil }
    }

    func handle(url: URL) {
        guard url.scheme == "shuru" else { return }
        switch url.host ?? "" {
        case "pause": requestPause()
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

    func requestPause() {
        guard data.settings.pause else { go(to: .now); return }
        if let until = data.pauseCooldownUntil, until > Date() {
            openInstagram()
            return
        }
        page = .now
        breathPhase = nil
        pauseStage = pauseStages.first
    }

    func advancePause() {
        guard let current = pauseStage else { return }
        let stages = pauseStages
        if let i = stages.firstIndex(of: current), i + 1 < stages.count {
            pauseStage = stages[i + 1]
        } else {
            pauseStage = .decide
        }
        breathPhase = nil
    }

    func endPause() {
        pauseStage = nil
        breathPhase = nil
    }

    func backToInstagram() {
        data.pauseCooldownUntil = Date().addingTimeInterval(TimeInterval(data.settings.snoozeMinutes * 60))
        endPause()
        openInstagram()
    }

    func openInstagram() {
        if let url = URL(string: "instagram://app") {
            UIApplication.shared.open(url, options: [:]) { ok in
                if !ok, let web = URL(string: "https://instagram.com") {
                    UIApplication.shared.open(web)
                }
            }
        }
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
    func queue(day: String = Day.today) -> [NowItem] {
        let nowMinutes = Day.calendar.component(.hour, from: Date()) * 60 + Day.calendar.component(.minute, from: Date())
        var entries: [(item: NowItem, bucket: Int, minutes: Int, order: Int)] = []
        var order = 0

        for r in data.routines where r.enabled && r.runs(on: day) && !r.steps.isEmpty {
            let base = "r:" + r.id.uuidString + "@" + day
            let idx = data.progress[base] ?? 0
            guard idx < r.steps.count else { continue }
            let item = NowItem(kind: .routine, refID: r.id, day: day, stepIndex: idx, stepCount: r.steps.count,
                               step: r.steps[idx], triggerLabel: r.trigger.label, rolledFrom: nil)
            let timed = r.trigger.kind == .time
            let bucket = timed ? (r.trigger.minutesOfDay <= nowMinutes ? 0 : 2) : 1
            entries.append((item, bucket, timed ? r.trigger.minutesOfDay : 0, order))
            order += 1
        }

        for t in tasks(on: day) where !t.isDone(on: day) && !t.steps.isEmpty {
            let base = "t:" + t.id.uuidString + "@" + day
            let idx = data.progress[base] ?? 0
            guard idx < t.steps.count else { continue }
            let rolled = (!t.isRepeating && t.date < day) ? t.date : nil
            var label = t.timeLabel ?? "Today"
            if let rolled { label = "From " + Day.shortWeekdays[Day.weekday(rolled) - 1] }
            let item = NowItem(kind: .task, refID: t.id, day: day, stepIndex: idx, stepCount: t.steps.count,
                               step: t.steps[idx], triggerLabel: label, rolledFrom: rolled)
            let minutes = t.timeHour.map { $0 * 60 + t.timeMinute }
            let bucket = minutes.map { $0 <= nowMinutes ? 0 : 2 } ?? 1
            entries.append((item, bucket, minutes ?? 0, order))
            order += 1
        }

        entries.sort { a, b in
            if a.bucket != b.bucket { return a.bucket < b.bucket }
            if a.minutes != b.minutes { return a.minutes < b.minutes }
            return a.order < b.order
        }
        var items = entries.map { $0.item }

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
        return items
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
        data.completions.append(Completion(title: item.step.title, typeID: item.step.typeID, at: Date(), refID: item.refID,
                                           isRoutine: item.kind == .routine, stepIndex: item.stepIndex,
                                           finishedWhole: whole, earnedToken: earned))
        if whole {
            data.notNow[item.day]?.removeAll { $0 == base }
            if data.pinned[item.day] == base { data.pinned[item.day] = nil }
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
    }

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
        let h = Day.calendar.component(.hour, from: Date())
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
        let to = Day.calendar.component(.hour, from: Date())
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
            data.completions.append(Completion(title: task.title, typeID: task.typeID, at: Date(), refID: task.id,
                                               isRoutine: false, stepIndex: max(0, task.steps.count - 1),
                                               finishedWhole: true, earnedToken: earned))
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
                    days: [2, 3, 4, 5, 6]),
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
