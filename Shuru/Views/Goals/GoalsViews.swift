import SwiftUI

struct MonthReviewRequest: Identifiable, Equatable {
    let month: String
    var id: String { month }
}

struct GoalEditRequest: Identifiable {
    let id = UUID()
    var goal: Goal?
    var month: String
}

// MARK: - Calendar card

/// The month's goals, at the top of Calendar. Folds away to one line.
struct GoalsCard: View {
    @EnvironmentObject var store: AppStore
    let month: String
    let edit: (GoalEditRequest) -> Void
    @AppStorage("goalsFolded") private var folded = false

    var body: some View {
        let goals = store.goals(in: month)
        let current = Day.monthKey(Day.today)
        let accent = Theme.accent(store.settings.palette)
        let lastMonth = Day.addMonths(-1, to: current)
        let offerLookBack = month == current && Day.dayNumber(Day.today) <= 7
            && !store.goals(in: lastMonth).isEmpty && !store.data.monthsReviewed.contains(lastMonth)

        if goals.isEmpty && !offerLookBack {
            if month < current {
                rowButton(icon: "calendar", title: Day.monthName(month) + " in review", subtitle: "What got done that month", accent: accent) {
                    store.monthReview = MonthReviewRequest(month: month)
                }
            } else {
                rowButton(icon: "scope", title: "Goals for " + Day.monthName(month),
                          subtitle: "Optional. Up to 3 things this month should move.", accent: accent) {
                    edit(GoalEditRequest(goal: nil, month: month))
                }
            }
        } else {
            Card {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { folded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text(Day.monthName(month) + " goals").font(.system(size: 16, weight: .semibold))
                        if folded && !goals.isEmpty {
                            Text(foldedSummary(goals)).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: folded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Day.monthName(month) + " goals, " + (folded ? "folded" : "open"))

                if !folded {
                    if offerLookBack {
                        lookBackRow(lastMonth, accent: accent)
                    }
                    ForEach(goals) { g in
                        GoalRow(goal: g, accent: accent) { edit(GoalEditRequest(goal: g, month: month)) }
                    }
                    HStack(spacing: 0) {
                        if goals.count < 3 && month >= current {
                            Button {
                                edit(GoalEditRequest(goal: nil, month: month))
                            } label: {
                                Label("Add a goal", systemImage: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(minHeight: 44)
                                    .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(accent)
                        }
                        Spacer()
                        if !goals.isEmpty {
                            Button(month < current ? "Month review" : "Month so far") {
                                store.monthReview = MonthReviewRequest(month: month)
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 16)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func foldedSummary(_ goals: [Goal]) -> String {
        let reached = goals.filter { (store.fraction($0) ?? 0) >= 1 }.count
        let withMin = goals.filter { $0.minimum != nil }.count
        if withMin > 0 { return "\(reached) of \(withMin) minimums reached" }
        return "\(goals.count) goal" + (goals.count == 1 ? "" : "s")
    }

    private func lookBackRow(_ lastMonth: String, accent: Color) -> some View {
        Button {
            store.monthReview = MonthReviewRequest(month: lastMonth)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill").font(.system(size: 20)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look back at " + Day.monthName(lastMonth)).font(.system(size: 15, weight: .semibold))
                    Text("See what moved, and keep any goal going.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowButton(icon: String, title: String, subtitle: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct GoalRow: View {
    @EnvironmentObject var store: AppStore
    let goal: Goal
    let accent: Color
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title)
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.leading)
                if let f = store.fraction(goal) {
                    GoalBar(fraction: f, tint: accent)
                }
                Text(store.progressText(goal))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit goal")
    }
}

struct GoalBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.checkbox.opacity(0.3))
                if fraction > 0 {
                    Capsule().fill(tint).frame(width: max(6, geo.size.width * CGFloat(min(1, fraction))))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Editor

private struct GoalCandidate: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let isRoutine: Bool
}

struct GoalEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let request: GoalEditRequest
    var showTags = true
    var onSave: ((Goal) -> Void)? = nil

    @State private var goal = Goal(title: "", month: "")
    @State private var hasMinimum = false
    @State private var minimum = 8
    @State private var tagged: Set<UUID> = []
    @State private var loaded = false
    @State private var confirmDelete = false

    private var editing: Bool { request.goal != nil }
    private var monthFull: Bool { !editing && store.goals(in: goal.month).count >= 3 }
    private var canSave: Bool { !goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !monthFull }
    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Pass the stats exam", text: $goal.title, axis: .vertical)
                        .font(.system(size: 17, weight: .medium))
                } header: {
                    Text("Goal for " + Day.monthName(goal.month))
                } footer: {
                    Text("A sentence is enough. Goals never show on Now, so they won’t crowd the task in front of you.")
                }

                if !editing {
                    Section {
                        Picker("Month", selection: $goal.month) {
                            ForEach(monthChoices, id: \.self) { m in Text(Day.monthName(m)).tag(m) }
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        if monthFull { Text(Day.monthName(goal.month) + " already has 3 goals.") }
                    }
                }

                Section {
                    Toggle("Set a minimum", isOn: $hasMinimum.animation())
                    if hasMinimum {
                        Picker("Count", selection: $goal.unit) {
                            ForEach(GoalUnit.allCases) { u in Text(u.name).tag(u) }
                        }
                        .pickerStyle(.segmented)
                        Stepper(value: $minimum, in: 1...(goal.unit == .steps ? 100 : 200)) {
                            Text("At least \(minimum) " + unitWord)
                                .font(.system(size: 16).monospacedDigit())
                        }
                    }
                } header: {
                    Text("Minimum")
                } footer: {
                    Text(minimumFooter)
                }

                if showTags {
                    Section {
                        let chosen = candidates.filter { tagged.contains($0.id) }
                        ForEach(chosen) { c in
                            HStack(spacing: 10) {
                                Image(systemName: c.isRoutine ? "repeat" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(c.title)
                            }
                        }
                        NavigationLink {
                            tagList
                        } label: {
                            Text(chosen.isEmpty ? "Choose tasks and routines" : "Change")
                                .foregroundStyle(accent)
                        }
                    } header: {
                        Text("Tasks and routines that move it")
                    } footer: {
                        Text("You can also pick a goal when you make or edit a task. Each step you finish on these counts.")
                    }
                }

                if editing {
                    Section {
                        Button("Delete goal", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Tasks keep their history. They just stop counting toward this.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing ? "Edit goal" : "New goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave).fontWeight(.semibold)
                }
            }
            .confirmationDialog("Delete this goal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(goal: goal.id)
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
    }

    private var tagList: some View {
        List {
            ForEach(candidates) { c in
                Button {
                    if tagged.contains(c.id) { tagged.remove(c.id) } else { tagged.insert(c.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: c.isRoutine ? "repeat" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).foregroundStyle(.primary)
                            Text(c.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if tagged.contains(c.id) {
                            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tagged.contains(c.id) ? .isSelected : [])
            }
            if candidates.isEmpty {
                Text("No open tasks or routines yet.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Moves it forward")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthChoices: [String] {
        let base = request.month
        return [base, Day.addMonths(1, to: base)]
    }

    private var unitWord: String {
        goal.unit == .steps ? (minimum == 1 ? "step" : "steps") : (minimum == 1 ? "hour" : "hours")
    }

    private var minimumFooter: String {
        guard hasMinimum else { return "A floor, not a target. Hitting it means the month counted." }
        return goal.unit == .steps
            ? "Every step you finish on a tagged task or routine counts as one."
            : "Counts the time tagged steps take on Now, from when they come up until you finish them (up to 3 hours each). Rough, but honest."
    }

    private var candidates: [GoalCandidate] {
        let tasks = store.data.tasks
            .filter { $0.goalID == goal.id || $0.isRepeating || !$0.isDone(on: $0.date) }
            .sorted { $0.date < $1.date }
            .map { t in
                GoalCandidate(id: t.id, title: t.title,
                              detail: t.repeatDays.map { Day.daysLabel($0) } ?? Day.short(t.date),
                              isRoutine: false)
            }
        let routines = store.data.routines
            .filter { $0.enabled || $0.goalID == goal.id }
            .map { r in GoalCandidate(id: r.id, title: r.title, detail: "Routine · " + r.trigger.label, isRoutine: true) }
        return tasks + routines
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let g = request.goal {
            goal = g
            hasMinimum = g.minimum != nil
            minimum = g.minimum ?? 8
        } else {
            goal = Goal(title: "", month: request.month)
        }
        let id = goal.id
        tagged = Set(store.data.tasks.filter { $0.goalID == id }.map(\.id)
                     + store.data.routines.filter { $0.goalID == id }.map(\.id))
    }

    private func save() {
        var g = goal
        g.title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.title.isEmpty else { return }
        g.minimum = hasMinimum ? minimum : nil
        store.upsert(goal: g)
        if showTags { store.setTags(goal: g.id, items: tagged) }
        onSave?(g)
        dismiss()
    }
}

// MARK: - Month review

private struct DoneGroup: Identifiable {
    let title: String
    let count: Int
    let last: String
    var id: String { title }
}

private struct OpenThing: Identifiable {
    let id: UUID
    let title: String
    let detail: String
}

/// What moved toward each goal this month, and what's still open.
struct MonthReviewView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let month: String
    @State private var editing: GoalEditRequest?

    private var accent: Color { Theme.accent(store.settings.palette) }
    private var current: String { Day.monthKey(Day.today) }
    private var isCurrent: Bool { month == current }
    /// Whether to look ahead: past months, or the last week of this one.
    private var lookAhead: Bool { !isCurrent || store.monthIsEnding }

    var body: some View {
        let goals = store.goals(in: month)
        let done = store.data.completions.filter { Day.monthKey($0.day) == month }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Day.monthName(month) + (isCurrent ? " so far" : ""))
                            .font(.system(size: 28, weight: .bold))
                        Text("Not a grade. Just what moved.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    statsCard(done: done, goals: goals)
                    ForEach(goals) { g in goalCard(g, done: done) }
                    if goals.isEmpty {
                        Text("No goals were set for " + Day.monthName(month) + ".")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    if lookAhead { nextMonthCard }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Month review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { req in
                GoalEditor(request: req)
            }
        }
        .onAppear {
            if lookAhead { store.data.monthsReviewed.insert(month) }
        }
    }

    // MARK: Pieces

    private func statsCard(done: [Completion], goals: [Goal]) -> some View {
        let ids = Set(goals.map(\.id))
        let toward = done.filter { c in c.goalID.map { ids.contains($0) } ?? false }.count
        let days = isCurrent ? Day.dayNumber(Day.today) : Day.daysIn(month: month)
        return Card {
            statRow("Days you showed up", "\(Set(done.map(\.day)).count) of \(days)")
            statRow("Steps finished", "\(done.count)")
            if !goals.isEmpty { statRow("Toward your goals", "\(toward)") }
            statRow("Routines completed", "\(done.filter { $0.isRoutine && $0.finishedWhole }.count)")
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 16))
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func goalCard(_ g: Goal, done: [Completion]) -> some View {
        let mine = done.filter { $0.goalID == g.id }
        let groups = grouped(mine)
        let open = openThings(g)
        let p = store.progress(g)
        let target = store.nextGoalMonth(after: month)
        let carried = store.isCarried(g)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                editing = GoalEditRequest(goal: g, month: month)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(g.title).font(.system(size: 18, weight: .semibold)).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit goal")
            if let f = store.fraction(g) { GoalBar(fraction: f, tint: accent) }
            Text(store.progressText(g) + (g.unit == .steps && p.hours >= 0.1 ? String(format: " · %.1f h", p.hours) : ""))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            sectionLabel("Got done")
            if groups.isEmpty {
                Text(isCurrent ? "Nothing tagged has been finished yet. One small step is enough to start." : "Nothing tagged got finished.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            ForEach(groups.prefix(8)) { d in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(accent)
                    Text(d.title).font(.system(size: 15)).lineLimit(2)
                    Spacer(minLength: 6)
                    if d.count > 1 {
                        Text("×\(d.count)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(Day.short(d.last)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if groups.count > 8 {
                Text("+\(groups.count - 8) more").font(.system(size: 13)).foregroundStyle(.secondary)
            }

            if !open.isEmpty {
                sectionLabel("Still open")
                ForEach(open.prefix(6)) { o in
                    HStack(spacing: 10) {
                        Image(systemName: "circle").font(.system(size: 15)).foregroundStyle(.secondary)
                        Text(o.title).font(.system(size: 15)).lineLimit(2)
                        Spacer(minLength: 6)
                        Text(o.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if open.count > 6 {
                    Text("+\(open.count - 6) more").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

            if lookAhead && target != month {
                Button {
                    withAnimation { _ = store.carryOver(g, to: target) }
                } label: {
                    Label(carried ? "Continues in " + Day.monthName(target) : "Keep going in " + Day.monthName(target),
                          systemImage: carried ? "checkmark" : "arrow.right.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(carried ? Color.secondary : accent)
                .disabled(carried || (store.goals(in: target).count >= 3))
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var nextMonthCard: some View {
        let target = store.nextGoalMonth(after: month)
        let next = store.goals(in: target)
        VStack(alignment: .leading, spacing: 10) {
            Text(target == month ? "Still time this month" : "Next: " + Day.monthName(target))
                .font(.system(size: 18, weight: .semibold))
            if next.isEmpty {
                Text("No goals yet. Pick up to 3, or none. Shuru works fine without them.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            ForEach(next) { g in
                HStack(spacing: 10) {
                    Image(systemName: "scope").font(.system(size: 14)).foregroundStyle(accent)
                    Text(g.title).font(.system(size: 15))
                }
            }
            if next.count < 3 {
                Button {
                    editing = GoalEditRequest(goal: nil, month: target)
                } label: {
                    Label("Add a goal for " + Day.monthName(target), systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func grouped(_ items: [Completion]) -> [DoneGroup] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var last: [String: String] = [:]
        var titles: [String: String] = [:]
        for c in items {
            let key = c.title.lowercased()
            if counts[key] == nil { order.append(key); titles[key] = c.title }
            counts[key, default: 0] += 1
            last[key] = max(last[key] ?? "", c.day)
        }
        return order
            .map { DoneGroup(title: titles[$0] ?? $0, count: counts[$0] ?? 0, last: last[$0] ?? "") }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }
    }

    private func openThings(_ g: Goal) -> [OpenThing] {
        let today = Day.today
        let tasks = store.data.tasks
            .filter { $0.goalID == g.id && ($0.isRepeating || !$0.isDone(on: $0.date)) }
            .sorted { $0.date < $1.date }
            .map { t -> OpenThing in
                let detail: String
                if let days = t.repeatDays { detail = Day.daysLabel(days) }
                else if t.date < today { detail = "From " + Day.short(t.date) }
                else { detail = Day.short(t.date) }
                return OpenThing(id: t.id, title: t.title, detail: detail)
            }
        let routines = store.data.routines
            .filter { $0.goalID == g.id && $0.enabled }
            .map { OpenThing(id: $0.id, title: $0.title, detail: "Routine") }
        return tasks + routines
    }
}
