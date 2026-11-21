import SwiftUI

/// A week strip with past days (what got done) and future days (what's planned).
struct CalendarView: View {
    @EnvironmentObject var store: AppStore

    enum Mode: String, CaseIterable, Identifiable {
        case day, week
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
    }

    @State private var selected = Day.today
    @State private var mode: Mode = .day
    @State private var energy = 2
    @State private var draft = ""
    @State private var picked: UUID?
    @State private var showDone = true
    @State private var composer: ComposerRequest?
    @State private var goalEdit: GoalEditRequest?
    @FocusState private var draftFocused: Bool

    private var today: String { Day.today }
    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PageScroll {
                header
                WeekStrip(selected: $selected, mode: $mode)
                GoalsCard(month: Day.monthKey(selected)) { goalEdit = $0 }
                if mode == .day {
                    if selected == today {
                        todayContent
                    } else if selected < today {
                        pastContent
                    } else {
                        futureContent
                    }
                } else {
                    weekContent
                }
            }
            FloatingAddButton(label: "Add a task", tint: accent) {
                composer = ComposerRequest(mode: .task, day: selected)
            }
        }
        .sheet(item: $composer) { req in
            ComposerView(request: req)
        }
        .sheet(item: $goalEdit) { req in
            GoalEditor(request: req)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Day.monthYear(selected))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if selected != today || mode == .week {
                    Button("Today") {
                        selected = today
                        mode = .day
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minHeight: 40)
                    .padding(.horizontal, 6)
                }
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.name).tag(m) }
                }
                .pickerStyle(.segmented)
                .frame(width: 124)
            }
            .frame(minHeight: 40)
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 4)
    }

    private var title: String {
        if mode == .week {
            let start = store.weekStart(of: selected)
            let thisWeek = store.weekStart(of: today)
            let diff = (Day.calendar.dateComponents([.day], from: Day.date(thisWeek), to: Day.date(start)).day ?? 0) / 7
            switch diff {
            case 0: return "This week"
            case 1: return "Next week"
            case -1: return "Last week"
            default:
                let end = Day.add(6, to: start)
                return "\(Day.dayNumber(start)) – \(Day.dayNumber(end)) " + String(Day.monthYear(end).prefix(3))
            }
        }
        if selected == today { return "Today" }
        if selected == Day.add(1, to: today) { return "Tomorrow" }
        if selected == Day.add(-1, to: today) { return "Yesterday" }
        return Day.longWeekdays[Day.weekday(selected) - 1] + " " + String(Day.dayNumber(selected))
    }

    // MARK: Today

    @ViewBuilder
    private var todayContent: some View {
        HStack(spacing: 12) {
            Text("Energy").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Picker("Energy right now", selection: $energy) {
                Text("Low").tag(1)
                Text("Okay").tag(2)
                Text("High").tag(3)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 4)

        let open = store.tasks(on: today).filter { !$0.isDone(on: today) && $0.effort <= energy }
        Card {
            CardHeader("Up next")
            ForEach(open) { t in
                TaskRow(task: t, day: today, highlighted: picked == t.id, accent: accent) {
                    store.toggleTask(t, day: today)
                } onEdit: {
                    composer = ComposerRequest(mode: .task, day: today, task: t)
                }
            }
            if open.isEmpty {
                Text(energy < 3 ? "Nothing that fits this energy. Try a higher setting." : "Nothing left. Add something, or rest.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            InlineAdd(text: $draft, placeholder: "Add a task for today", focused: $draftFocused, accent: accent) {
                store.addTask(title: draft, day: today)
                draft = ""
            }
        }

        if open.count > 1 {
            Button {
                picked = open.filter { $0.id != picked }.randomElement()?.id
            } label: {
                Label("Pick one for me", systemImage: "shuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
        }

        routinesCard(day: today)

        let done = store.completions(on: today)
        if !done.isEmpty {
            Card {
                Button {
                    withAnimation { showDone.toggle() }
                } label: {
                    HStack {
                        Text("Completed").font(.system(size: 16, weight: .semibold))
                        Text("\(done.count)").font(.system(size: 14)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: showDone ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showDone {
                    ForEach(done.reversed()) { c in DoneRow(completion: c) }
                }
            }
        }
    }

    // MARK: Past and future days

    @ViewBuilder
    private var pastContent: some View {
        let done = store.completions(on: selected)
        Card {
            CardHeader("Done that day") {
                Text("\(done.count)").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if done.isEmpty {
                Text("Nothing logged. Rest days count too.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            ForEach(done) { c in DoneRow(completion: c) }
        }
        let missed = store.data.tasks.filter { !$0.isRepeating && $0.date == selected && !$0.isDone(on: selected) }
        if !missed.isEmpty {
            Card {
                CardHeader("Didn’t get to")
                ForEach(missed) { t in
                    HStack(spacing: 12) {
                        TypeDot(color: store.type(t.typeID).color)
                        Text(t.title).font(.system(size: 16))
                        Spacer()
                        Text("Moved to today").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
            }
        }
    }

    @ViewBuilder
    private var futureContent: some View {
        let planned = store.tasks(on: selected, includeRollover: false)
        Card {
            CardHeader("Planned")
            ForEach(planned) { t in
                TaskRow(task: t, day: selected, highlighted: false, accent: accent, onToggle: nil) {
                    composer = ComposerRequest(mode: .task, day: selected, task: t)
                }
            }
            if planned.isEmpty {
                Text("Nothing planned yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            InlineAdd(text: $draft, placeholder: "Add a task for " + Day.short(selected), focused: $draftFocused, accent: accent) {
                store.addTask(title: draft, day: selected)
                draft = ""
            }
        }
        routinesCard(day: selected)
    }

    @ViewBuilder
    private func routinesCard(day: String) -> some View {
        let rs = store.routines(on: day)
        if !rs.isEmpty {
            Card {
                CardHeader(day == today ? "Routines today" : "Routines that day")
                ForEach(rs) { r in
                    let p = store.progress(routine: r, day: day)
                    HStack(spacing: 12) {
                        Image(systemName: r.trigger.kind.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(store.type(r.steps.first?.typeID ?? "other").color)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.system(size: 16))
                            Text(r.trigger.label + (r.steps.count > 1 ? " · \(r.steps.count) steps" : ""))
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if day == today {
                            if r.trigger.isCue && !store.hasStarted(r) && !r.trigger.inWindow(), let w = r.trigger.windowLabel {
                                Text(w)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            } else if r.trigger.isCue && !store.hasStarted(r) {
                                Button("Start") { store.cueHappened(routineID: r.id, announce: false) }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Start " + r.title)
                            } else {
                                Text(p >= r.steps.count ? "Done" : (p > 0 ? "\(p) of \(r.steps.count)" : "Started"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(p >= r.steps.count ? accent : .secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
            }
        }
    }

    // MARK: Week

    @ViewBuilder
    private var weekContent: some View {
        let start = store.weekStart(of: selected)
        ForEach(0..<7, id: \.self) { i in
            WeekDayCard(day: Day.add(i, to: start)) {
                selected = Day.add(i, to: start)
                mode = .day
            }
        }
    }
}

// MARK: - Pieces

struct WeekStrip: View {
    @EnvironmentObject var store: AppStore
    @Binding var selected: String
    @Binding var mode: CalendarView.Mode

    var body: some View {
        let start = store.weekStart(of: selected)
        let today = Day.today
        let accent = Theme.accent(store.settings.palette)
        HStack(spacing: 0) {
            Button {
                selected = Day.add(-7, to: selected)
            } label: {
                Image(systemName: "chevron.left").frame(width: 34, height: 64)
            }
            .accessibilityLabel("Previous week")
            ForEach(0..<7, id: \.self) { i in
                let key = Day.add(i, to: start)
                let isSel = mode == .day ? key == selected : key == today
                let isToday = key == today
                Button {
                    selected = key
                    mode = .day
                } label: {
                    VStack(spacing: 4) {
                        Text(Day.letters[Day.weekday(key) - 1]).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text("\(Day.dayNumber(key))")
                            .font(.system(size: 16, weight: isSel || isToday ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(isSel ? Color.white : (isToday ? accent : (key < today ? Color.secondary : Color.primary)))
                            .frame(width: 34, height: 34)
                            .background(isSel ? accent : Color.clear, in: Circle())
                        Circle()
                            .fill(dotColor(key: key, today: today, accent: accent, selected: isSel))
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Day.longWeekdays[Day.weekday(key) - 1] + " " + String(Day.dayNumber(key)) + (isToday ? ", today" : ""))
                .accessibilityAddTraits(isSel ? .isSelected : [])
            }
            Button {
                selected = Day.add(7, to: selected)
            } label: {
                Image(systemName: "chevron.right").frame(width: 34, height: 64)
            }
            .accessibilityLabel("Next week")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, -10)
    }

    private func dotColor(key: String, today: String, accent: Color, selected: Bool) -> Color {
        if selected { return .clear }
        if key < today { return store.completions(on: key).isEmpty ? .clear : accent }
        if key > today { return store.tasks(on: key, includeRollover: false).isEmpty && store.routines(on: key).isEmpty ? .clear : Theme.checkbox }
        return .clear
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: AppStore
    let task: PlannedTask
    let day: String
    let highlighted: Bool
    let accent: Color
    let onToggle: (() -> Void)?
    let onEdit: () -> Void

    var body: some View {
        let done = task.isDone(on: day)
        let type = store.type(task.typeID)
        HStack(spacing: 12) {
            if let onToggle {
                Button(action: onToggle) {
                    CheckCircle(done: done, tint: accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "Mark not done" : "Mark done")
            } else {
                TypeDot(color: type.color).frame(width: 44)
            }
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 16))
                        .strikethrough(done)
                        .foregroundStyle(done ? .secondary : .primary)
                    Text(meta(type: type))
                        .font(.system(size: 13))
                        .foregroundStyle(highlighted ? accent : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 2)
        .padding(.trailing, 16)
        .frame(minHeight: 50)
        .background(highlighted ? accent.opacity(0.12) : Color.clear)
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(task: task.id) }
        }
    }

    private func meta(type: TaskType) -> String {
        var parts: [String] = []
        if highlighted { parts.append("Do this one") }
        if !task.isRepeating && task.date < day { parts.append("From " + Day.shortWeekdays[Day.weekday(task.date) - 1]) }
        if let t = task.timeLabel { parts.append(t) }
        if let days = task.repeatDays { parts.append(Day.daysLabel(days)) }
        parts.append(type.name)
        if task.steps.count > 1 { parts.append("\(task.steps.count) steps") }
        if let g = store.goal(task.goalID) {
            parts.append("Goal: " + (g.title.count > 26 ? String(g.title.prefix(25)) + "…" : g.title))
        }
        return parts.joined(separator: " · ")
    }
}

struct DoneRow: View {
    @EnvironmentObject var store: AppStore
    let completion: Completion

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(done: true, tint: Theme.checkbox)
                .frame(width: 44)
            Text(completion.title)
                .font(.system(size: 16))
                .strikethrough()
                .foregroundStyle(.secondary)
            Spacer()
            Text(Day.clock(completion.at))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 2)
        .padding(.trailing, 16)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

struct InlineAdd: View {
    @Binding var text: String
    let placeholder: String
    var focused: FocusState<Bool>.Binding
    let accent: Color
    let submit: () -> Void

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isEmpty { focused.wrappedValue = true } else { submit() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .focused(focused)
                .submitLabel(.done)
                .onSubmit {
                    // Nothing typed: the tick just puts the keyboard away.
                    if isEmpty { focused.wrappedValue = false } else { submit() }
                }
        }
        .padding(.leading, 2)
        .padding(.trailing, 16)
        .frame(minHeight: 48)
    }
}

struct WeekDayCard: View {
    @EnvironmentObject var store: AppStore
    let day: String
    let open: () -> Void

    var body: some View {
        let today = Day.today
        let accent = Theme.accent(store.settings.palette)
        let isPast = day < today
        let titles: [String] = isPast
            ? store.completions(on: day).map(\.title)
            : store.tasks(on: day, includeRollover: day == today).filter { !$0.isDone(on: day) }.map(\.title)
                + store.routines(on: day).map(\.title)
        let summary = isPast
            ? (titles.isEmpty ? "Rest day" : "\(titles.count) done")
            : (titles.isEmpty ? "Free" : "\(titles.count) " + (day == today ? "to do" : "planned"))
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Day.short(day))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(day == today ? accent : .primary)
                    Spacer()
                    Text(summary).font(.system(size: 13)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(titles.prefix(3).enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 10) {
                        Circle().fill(isPast ? Theme.checkbox : accent.opacity(0.8)).frame(width: 5, height: 5)
                        Text(t)
                            .font(.system(size: 15))
                            .strikethrough(isPast)
                            .foregroundStyle(isPast ? .secondary : .primary)
                            .lineLimit(1)
                    }
                }
                if titles.count > 3 {
                    Text("+\(titles.count - 3) more").font(.system(size: 14)).foregroundStyle(.secondary).padding(.leading, 15)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Day.short(day) + ": " + summary)
    }
}
