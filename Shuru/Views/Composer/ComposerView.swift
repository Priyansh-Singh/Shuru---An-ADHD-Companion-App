import SwiftUI

/// What to open the composer with.
struct ComposerRequest: Identifiable {
    enum Mode: String, CaseIterable, Identifiable {
        case task, routine
        var id: String { rawValue }
        var name: String { self == .task ? "Task" : "Routine" }
    }

    let id = UUID()
    var mode: Mode
    var day: String = Day.today
    var task: PlannedTask? = nil
    var routine: Routine? = nil
    /// True when task/routine is only a starting point (a template), not something to edit.
    var prefill = false
    /// True when this makes or edits one of your templates instead of a real routine.
    var asTemplate = false
}

enum RepeatChoice: String, CaseIterable, Identifiable {
    case once, everyDay, weekdays, weekends, custom
    var id: String { rawValue }
    var name: String {
        switch self {
        case .once: return "Once"
        case .everyDay: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .custom: return "Pick days"
        }
    }

    static func from(_ days: Set<Int>?) -> RepeatChoice {
        guard let days else { return .once }
        if days.isEmpty || days.count == 7 { return .everyDay }
        if days == [2, 3, 4, 5, 6] { return .weekdays }
        if days == [1, 7] { return .weekends }
        return .custom
    }
}

/// The + button: a task or a routine, with steps, a type, how long, when and how often.
struct ComposerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let request: ComposerRequest

    @State private var mode: ComposerRequest.Mode = .task
    @State private var steps: [Step] = [Step(title: "")]
    @State private var date = Date()
    @State private var hasTime = false
    @State private var time = Date()
    @State private var effort = 2
    @State private var trigger = Trigger()
    @State private var repeatChoice: RepeatChoice = .once
    @State private var days: Set<Int> = Set(1...7)
    @State private var backup = ""
    @State private var breather = 0
    @State private var loaded = false
    @State private var newTypeFor: UUID?
    @State private var newTypeName = ""
    @State private var confirmDelete = false
    @State private var savedTemplate = false
    @FocusState private var focusedStep: UUID?

    private var editing: Bool { !request.prefill && (request.task != nil || request.routine != nil) }
    private var canSave: Bool { !(steps.first?.title.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }

    var body: some View {
        NavigationStack {
            Form {
                if !editing && !request.asTemplate {
                    Section {
                        Picker("Kind", selection: $mode) {
                            ForEach(ComposerRequest.Mode.allCases) { m in Text(m.name).tag(m) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                ForEach($steps) { $step in
                    StepEditorSection(step: $step,
                                      index: steps.firstIndex(where: { $0.id == step.id }) ?? 0,
                                      count: steps.count,
                                      types: store.data.types,
                                      focus: $focusedStep,
                                      onNewType: { newTypeFor = step.id },
                                      onRemove: { steps.removeAll { $0.id == step.id } })
                }

                Section {
                    Button {
                        let last = steps.last
                        let s = Step(title: "", typeID: last?.typeID ?? "other")
                        steps.append(s)
                        focusedStep = s.id
                    } label: {
                        Label("Then… chain the next step", systemImage: "link")
                    }
                } footer: {
                    Text("Chained steps show up one at a time on Now, in order.")
                }

                whenSection
                repeatSection

                if mode == .routine {
                    Section("If it doesn’t happen") {
                        TextField("Backup plan, e.g. at least 10 minutes", text: $backup)
                        if steps.count > 1 {
                            Stepper("Breather between steps: \(breather) min", value: $breather, in: 0...30, step: 5)
                        }
                    }
                }

                if mode == .routine && !request.asTemplate {
                    Section {
                        Button {
                            saveCopyAsTemplate()
                        } label: {
                            Label(savedTemplate ? "Saved as a template" : "Save a copy as a template",
                                  systemImage: savedTemplate ? "checkmark" : "square.on.square")
                        }
                        .disabled(savedTemplate || !canSave)
                    } footer: {
                        Text("Templates show up at the bottom of Routines, ready to reuse.")
                    }
                }

                if editing {
                    Section {
                        Button(deleteLabel, role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).fontWeight(.semibold)
                }
            }
            .alert("New type", isPresented: Binding(get: { newTypeFor != nil }, set: { if !$0 { newTypeFor = nil } })) {
                TextField("Name, e.g. Assignment", text: $newTypeName)
                Button("Add") { addType() }
                Button("Cancel", role: .cancel) { newTypeName = "" }
            } message: {
                Text("Types are the tags on your tasks. They colour the calendar and your hours.")
            }
            .confirmationDialog("Delete this for good?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteExisting() }
            }
        }
        .onAppear(perform: load)
    }

    private var title: String {
        if request.asTemplate { return editing ? "Edit template" : "New template" }
        if editing { return mode == .task ? "Edit task" : "Edit routine" }
        return mode == .task ? "New task" : "New routine"
    }

    private var deleteLabel: String {
        if request.asTemplate { return "Delete template" }
        return mode == .task ? "Delete task" : "Delete routine"
    }

    // MARK: Sections

    @ViewBuilder
    private var whenSection: some View {
        if mode == .task {
            Section("When") {
                DatePicker("Day", selection: $date, displayedComponents: .date)
                Toggle("At a set time", isOn: $hasTime.animation())
                if hasTime {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                Picker("Energy it needs", selection: $effort) {
                    Text("Low").tag(1)
                    Text("Okay").tag(2)
                    Text("High").tag(3)
                }
            }
        } else {
            Section {
                Picker("When", selection: $trigger.kind) {
                    ForEach(TriggerKind.allCases) { k in
                        Label(k.name, systemImage: k.symbol).tag(k)
                    }
                }
                if trigger.kind == .time {
                    DatePicker("Time", selection: triggerTime, displayedComponents: .hourAndMinute)
                } else {
                    TextField(trigger.kind.placeholder, text: $trigger.text)
                }
            } header: {
                Text("If…")
            } footer: {
                Text(trigger.kind == .time ? "You’ll get a reminder at this time." : "Write it the way you’d say it, like “When I get home”.")
            }
        }
    }

    @ViewBuilder
    private var repeatSection: some View {
        Section("Repeat") {
            Picker("Repeat", selection: $repeatChoice) {
                ForEach(RepeatChoice.allCases.filter { mode == .task || $0 != .once }) { c in
                    Text(c.name).tag(c)
                }
            }
            if repeatChoice == .custom {
                DaysPicker(days: $days)
            }
        }
        .onChange(of: mode) { _, m in
            if m == .routine && repeatChoice == .once { repeatChoice = .everyDay }
        }
    }

    private var triggerTime: Binding<Date> {
        Binding(
            get: {
                Day.calendar.date(bySettingHour: trigger.hour, minute: trigger.minute, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Day.calendar.dateComponents([.hour, .minute], from: d)
                trigger.hour = c.hour ?? 19
                trigger.minute = c.minute ?? 0
            }
        )
    }

    // MARK: Load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        mode = request.mode
        date = Day.date(request.day)
        if let t = request.task {
            mode = .task
            steps = t.steps.isEmpty ? [Step(title: "")] : t.steps
            date = Day.date(t.date)
            if let h = t.timeHour {
                hasTime = true
                time = Day.calendar.date(bySettingHour: h, minute: t.timeMinute, second: 0, of: Date()) ?? Date()
            }
            effort = t.effort
            repeatChoice = RepeatChoice.from(t.repeatDays)
            days = t.repeatDays ?? Set(1...7)
        } else if let r = request.routine {
            mode = .routine
            steps = r.steps.isEmpty ? [Step(title: "")] : r.steps
            trigger = r.trigger
            repeatChoice = RepeatChoice.from(r.days)
            days = r.days
            backup = r.backup
            breather = r.breatherMinutes
        } else {
            repeatChoice = request.mode == .routine ? .everyDay : .once
            focusedStep = steps.first?.id
        }
    }

    private var chosenDays: Set<Int>? {
        switch repeatChoice {
        case .once: return nil
        case .everyDay: return Set(1...7)
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekends: return [1, 7]
        case .custom: return days.isEmpty ? Set(1...7) : days
        }
    }

    private func cleanedSteps() -> [Step] {
        steps.compactMap { s in
            var s = s
            s.title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
            s.subs = s.subs.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            return s.title.isEmpty ? nil : s
        }
    }

    private func save() {
        let cleaned = cleanedSteps()
        guard !cleaned.isEmpty else { return }
        if mode == .task {
            var t = request.task ?? PlannedTask(steps: cleaned, date: Day.key(date))
            t.steps = cleaned
            t.date = Day.key(date)
            t.repeatDays = chosenDays
            if hasTime {
                let c = Day.calendar.dateComponents([.hour, .minute], from: time)
                t.timeHour = c.hour
                t.timeMinute = c.minute ?? 0
            } else {
                t.timeHour = nil
                t.timeMinute = 0
            }
            t.effort = effort
            store.upsert(task: t)
        } else {
            var r = request.routine ?? Routine()
            r.steps = cleaned
            r.trigger = trigger
            r.days = chosenDays ?? Set(1...7)
            r.backup = backup.trimmingCharacters(in: .whitespaces)
            r.breatherMinutes = breather
            if request.asTemplate {
                store.upsert(template: r)
            } else {
                store.upsert(routine: r)
            }
        }
        dismiss()
    }

    private func saveCopyAsTemplate() {
        let cleaned = cleanedSteps()
        guard !cleaned.isEmpty else { return }
        var r = Routine()
        r.steps = cleaned.map { s in
            var c = s
            c.id = UUID()
            c.subs = s.subs.map { SubStep(title: $0.title) }
            return c
        }
        r.trigger = trigger
        r.days = chosenDays ?? Set(1...7)
        r.backup = backup.trimmingCharacters(in: .whitespaces)
        r.breatherMinutes = breather
        store.upsert(template: r)
        withAnimation { savedTemplate = true }
    }

    private func deleteExisting() {
        if let t = request.task { store.delete(task: t.id) }
        if let r = request.routine {
            if request.asTemplate { store.delete(template: r.id) } else { store.delete(routine: r.id) }
        }
        dismiss()
    }

    private func addType() {
        let name = newTypeName.trimmingCharacters(in: .whitespaces)
        defer { newTypeName = ""; newTypeFor = nil }
        guard !name.isEmpty, let target = newTypeFor else { return }
        let used = Set(store.data.types.map(\.colorHex))
        let color = TaskType.swatches.first { !used.contains($0) } ?? TaskType.swatches[store.data.types.count % TaskType.swatches.count]
        let t = store.addType(name: name, colorHex: color)
        if let i = steps.firstIndex(where: { $0.id == target }) { steps[i].typeID = t.id }
    }
}

// MARK: - One step

private let minuteOptions = [1, 2, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120, 180, 240]

struct StepEditorSection: View {
    @Binding var step: Step
    let index: Int
    let count: Int
    let types: [TaskType]
    var focus: FocusState<UUID?>.Binding
    let onNewType: () -> Void
    let onRemove: () -> Void

    private var hasLimits: Binding<Bool> {
        Binding(
            get: { step.minMinutes != nil || step.maxMinutes != nil },
            set: { on in
                if on {
                    step.minMinutes = 2
                    step.maxMinutes = 30
                } else {
                    step.minMinutes = nil
                    step.maxMinutes = nil
                }
            }
        )
    }

    var body: some View {
        Section {
            TextField(index == 0 ? "What’s the first thing?" : "Then what?", text: $step.title, axis: .vertical)
                .font(.system(size: 17, weight: .medium))
                .focused(focus, equals: step.id)

            HStack {
                Picker("Type", selection: $step.typeID) {
                    ForEach(types) { t in
                        Text(t.name).tag(t.id)
                    }
                }
                TypeDot(color: types.first { $0.id == step.typeID }?.color ?? .gray, size: 10)
            }
            Button("New type…", action: onNewType)
                .buttonStyle(.borderless)

            Toggle("How long", isOn: hasLimits.animation())
            if hasLimits.wrappedValue {
                Picker("At least", selection: Binding(get: { step.minMinutes ?? 2 }, set: { step.minMinutes = $0 })) {
                    ForEach(minuteOptions, id: \.self) { m in Text(Step.duration(m)).tag(m) }
                }
                Picker("Stop by", selection: Binding(get: { step.maxMinutes ?? 30 }, set: { step.maxMinutes = $0 })) {
                    ForEach(minuteOptions, id: \.self) { m in Text(Step.duration(m)).tag(m) }
                }
            }

            TextField("Smaller version, e.g. Just open the doc", text: $step.smaller)

            ForEach($step.subs) { $sub in
                HStack(spacing: 10) {
                    Button {
                        sub.done.toggle()
                    } label: {
                        Image(systemName: sub.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(sub.done ? "Done" : "Not done")
                    TextField("Small piece", text: $sub.title)
                    Button {
                        step.subs.removeAll { $0.id == sub.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove piece")
                }
            }
            Button {
                step.subs.append(SubStep(title: ""))
            } label: {
                Label("Break it into smaller pieces", systemImage: "list.bullet.indent")
            }
            .buttonStyle(.borderless)

            if count > 1 {
                Button("Remove this step", role: .destructive, action: onRemove)
                    .buttonStyle(.borderless)
            }
        } header: {
            Text(count > 1 ? "Step \(index + 1)" : "What")
        }
    }
}

// MARK: - Days

struct DaysPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { wd in
                let on = days.contains(wd)
                Button {
                    if on { days.remove(wd) } else { days.insert(wd) }
                } label: {
                    Text(Day.letters[wd - 1])
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(on ? Color.accentColor : Theme.card2, in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Day.longWeekdays[wd - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }
}
