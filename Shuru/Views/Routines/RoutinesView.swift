import SwiftUI

/// Things that happen when something else does, on the days you pick.
struct RoutinesView: View {
    @EnvironmentObject var store: AppStore
    @State private var composer: ComposerRequest?

    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        let today = Day.today
        let all = store.data.routines
        let todays = all.filter { $0.enabled && $0.runs(on: today) }
        let others = all.filter { $0.enabled && !$0.runs(on: today) }
        let paused = all.filter { !$0.enabled }

        ZStack(alignment: .bottomTrailing) {
            PageScroll {
                ScreenHeader(title: "Routines", subtitle: "Things that happen when something else does, on the days you pick.")

                if all.isEmpty {
                    Card(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                        Text("No routines yet. Start with a template below, or tap + to make your own.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
                if !todays.isEmpty { group("Today", todays) }
                if !others.isEmpty { group("Other days", others) }
                if !paused.isEmpty { group("Paused", paused) }

                Card(padding: EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16)) {
                    Text("Guardrails").font(.system(size: 16, weight: .semibold)).padding(.bottom, 6)
                    VStack(alignment: .leading, spacing: 6) {
                        guardrail("Keep the first step tiny. Two minutes is plenty.")
                        guardrail("Give every routine a backup plan for bad days.")
                        guardrail("Missed one? Nothing breaks. It’s back tomorrow.")
                    }
                }

                templatesSection
            }
            FloatingAddButton(label: "New routine", tint: accent) {
                composer = ComposerRequest(mode: .routine)
            }
        }
        .sheet(item: $composer) { req in
            ComposerView(request: req)
        }
    }

    // MARK: Templates

    private struct TemplateItem: Identifiable {
        let id: String
        let name: String
        let detail: String
        let symbol: String
        let userTemplate: Routine?
        let make: () -> Routine
    }

    private var templateItems: [TemplateItem] {
        let mine = store.data.templates.map { r in
            TemplateItem(id: "mine-" + r.id.uuidString,
                         name: r.hasName ? r.title : r.trigger.label,
                         detail: stepsSummary(r),
                         symbol: r.trigger.kind.symbol,
                         userTemplate: r,
                         make: {
                             var copy = r
                             copy.id = UUID()
                             copy.enabled = true
                             return copy
                         })
        }
        let builtIn = RoutineTemplate.all
            .filter { !store.data.hiddenTemplates.contains($0.id) }
            .map { t in
                TemplateItem(id: "built-" + t.id, name: t.name, detail: t.detail, symbol: t.symbol, userTemplate: nil, make: t.routine)
            }
        return mine + builtIn
    }

    private func stepsSummary(_ r: Routine) -> String {
        let titles: [String] = r.steps.prefix(3).map { $0.title }
        let joined: String = titles.joined(separator: ", ")
        return r.steps.count > 3 ? joined + "…" : joined
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Templates")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            ForEach(templateItems) { t in
                templateRow(t)
            }
            Button {
                composer = ComposerRequest(mode: .routine, asTemplate: true)
            } label: {
                HStack {
                    Image(systemName: "plus.square.on.square").foregroundStyle(accent).frame(width: 24)
                    Text("New template").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Long-press a template to edit or remove it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            if !store.data.hiddenTemplates.isEmpty {
                Button("Bring back the built-in templates") { store.restoreBuiltInTemplates() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func templateRow(_ t: TemplateItem) -> some View {
        Button {
            composer = ComposerRequest(mode: .routine, routine: t.make(), prefill: true)
        } label: {
            HStack {
                Image(systemName: t.symbol).foregroundStyle(accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(.system(size: 15, weight: .semibold))
                    Text(t.detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if t.userTemplate != nil {
                    Text("Yours").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                Image(systemName: "plus").foregroundStyle(accent)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts a new routine from this template")
        .contextMenu {
            if let mine = t.userTemplate {
                Button("Edit template", systemImage: "pencil") {
                    composer = ComposerRequest(mode: .routine, routine: mine, asTemplate: true)
                }
                Button("Delete template", systemImage: "trash", role: .destructive) {
                    store.delete(template: mine.id)
                }
            } else {
                Button("Remove template", systemImage: "eye.slash", role: .destructive) {
                    store.hideBuiltInTemplate(String(t.id.dropFirst("built-".count)))
                }
            }
        }
    }

    private func group(_ title: String, _ list: [Routine]) -> some View {
        Card {
            CardHeader(title)
            ForEach(list) { r in
                RoutineRow(routine: r) {
                    composer = ComposerRequest(mode: .routine, routine: r)
                }
            }
        }
    }

    private func guardrail(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(accent).frame(width: 5, height: 5).offset(y: -2)
            Text(text).font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }
}

struct RoutineRow: View {
    @EnvironmentObject var store: AppStore
    let routine: Routine
    let edit: () -> Void

    var body: some View {
        let type = store.type(routine.steps.first?.typeID ?? "other")
        HStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 12) {
                    Image(systemName: routine.trigger.kind.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(type.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.title)
                            .font(.system(size: 16))
                            .foregroundStyle(routine.enabled ? .primary : .secondary)
                        Text(subtitle(type: type))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        let streak = store.streak(routine)
                        if routine.enabled && streak >= 2 {
                            StreakBadge(count: streak, tint: Theme.accent(store.settings.palette))
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { routine.enabled }, set: { store.setEnabled(routine.id, $0) }))
                .labelsHidden()
                .accessibilityLabel(routine.enabled ? "Turn off " + routine.title : "Turn on " + routine.title)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .contextMenu {
            if routine.enabled && routine.trigger.isCue && routine.runs(on: Day.today) && !store.hasStarted(routine) {
                Button("Start now", systemImage: "play") { store.cueHappened(routineID: routine.id, announce: false) }
            }
            Button("Edit", systemImage: "pencil", action: edit)
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(routine: routine.id) }
        }
    }

    private func subtitle(type: TaskType) -> String {
        var parts = [routine.trigger.label, Day.daysLabel(routine.days), type.name]
        if routine.hasName, let first = routine.steps.first?.title { parts.insert("Starts with: " + first, at: 0) }
        if let w = routine.trigger.windowLabel { parts.append(w) }
        if routine.trigger.kind == .place && routine.trigger.place != nil { parts.append("Starts when you arrive") }
        if routine.steps.count > 1 { parts.append("\(routine.steps.count) steps") }
        if !routine.backup.isEmpty { parts.append("Backup: " + routine.backup) }
        return parts.joined(separator: " · ")
    }
}

struct RoutineTemplate: Identifiable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let routine: () -> Routine

    static let all: [RoutineTemplate] = [
        RoutineTemplate(id: "home", name: "Home from work or class", detail: "Bath, dinner, then study", symbol: "house") {
            Routine(trigger: Trigger(kind: .place, text: "When I get home", windowFrom: 15 * 60, windowTo: 21 * 60),
                    steps: [Step(title: "Take a bath", smaller: "Just turn on the water", typeID: "care"),
                            Step(title: "Eat dinner", smaller: "Just heat something up", typeID: "care"),
                            Step(title: "Sit down to study", smaller: "Just open your notes", typeID: "study", minMinutes: 2, maxMinutes: 180)],
                    days: [2, 3, 4, 5, 6], name: "Coming home")
        },
        RoutineTemplate(id: "morning", name: "Morning start", detail: "Water, meds, look at the day", symbol: "sunrise") {
            Routine(trigger: Trigger(kind: .time, hour: 8, minute: 0),
                    steps: [Step(title: "Drink a glass of water", smaller: "Just fill the glass", typeID: "care"),
                            Step(title: "Take your meds", smaller: "Just open the box", typeID: "care"),
                            Step(title: "Look at today’s plan", smaller: "Just open the calendar", typeID: "other")],
                    days: Set(1...7), name: "Morning start")
        },
        RoutineTemplate(id: "laundry", name: "Saturday laundry", detail: "Start a load, then fold", symbol: "washer") {
            Routine(trigger: Trigger(kind: .after, text: "After breakfast"),
                    steps: [Step(title: "Start a load of laundry", smaller: "Just gather the clothes", typeID: "chores"),
                            Step(title: "Fold and put away", smaller: "Just fold five things", typeID: "chores")],
                    days: [7], name: "Laundry")
        },
        RoutineTemplate(id: "bed", name: "Before bed", detail: "Keys by the door, phone on charge", symbol: "moon") {
            Routine(trigger: Trigger(kind: .time, hour: 22, minute: 30),
                    steps: [Step(title: "Put your keys by the door", smaller: "Just find your keys", typeID: "chores"),
                            Step(title: "Phone on charge, away from bed", smaller: "Just plug it in", typeID: "rest")],
                    days: Set(1...7), name: "Before bed")
        }
    ]
}
