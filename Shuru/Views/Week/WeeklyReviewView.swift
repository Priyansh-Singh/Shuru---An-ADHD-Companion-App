import SwiftUI

/// Five minutes: look back, clear what's slipping, pick up to 3 things that matter next.
struct WeeklyReviewView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    enum ReviewStep: Int, CaseIterable { case lookBack, slipping, goals, focus, done }

    @Environment(\.colorScheme) private var scheme
    @State private var step: ReviewStep = .lookBack
    @State private var focuses: [String] = ["", "", ""]
    @State private var earned = false
    @State private var composer: ComposerRequest?
    @State private var loaded = false
    @State private var goalSteps: [UUID: String] = [:]
    @State private var goalDays: [UUID: String] = [:]
    @State private var addedSteps = 0

    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        progressDots
                        switch step {
                        case .lookBack: lookBack
                        case .slipping: slipping
                        case .goals: goalsStep
                        case .focus: focusStep
                        case .done: doneStep
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                    .dismissesKeyboardOnBlankTap()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.background)
            .navigationTitle("Weekly review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .done ? "Close" : "Later") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if step != .done {
                    Button(action: next) {
                        Text(step == .focus ? "Save my week" : "Next")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.onAccent(scheme == .dark))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Theme.background)
                }
            }
            .sheet(item: $composer) { req in
                ComposerView(request: req)
            }
        }
        .onAppear(perform: load)
    }

    /// Goals for the week being planned (the month most of it falls in).
    private var reviewGoals: [Goal] {
        store.goals(in: Day.monthKey(Day.add(3, to: store.reviewTargetWeek())))
    }

    private var shownSteps: [ReviewStep] {
        ReviewStep.allCases.filter { $0 != .goals || !reviewGoals.isEmpty }
    }

    private var progressDots: some View {
        let at = shownSteps.firstIndex(of: step) ?? 0
        return HStack(spacing: 6) {
            ForEach(Array(shownSteps.enumerated()), id: \.offset) { pair in
                Capsule()
                    .fill(pair.offset <= at ? accent : Theme.checkbox.opacity(0.4))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: 1. Look back

    private var lookBack: some View {
        let today = Day.today
        let days = (0..<7).map { Day.add(-$0, to: today) }
        let done = store.data.completions.filter { days.contains($0.day) }
        let finished = done.filter { $0.finishedWhole }.count
        let routines = done.filter { $0.isRoutine && $0.finishedWhole }.count
        let showedUp = Set(done.map(\.day)).count
        let logged = days.reduce(0) { $0 + (store.data.hours[$1]?.count ?? 0) }
        let best = store.data.routines.filter { $0.enabled }.map { ($0, store.streak($0)) }.max { $0.1 < $1.1 }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Your last 7 days").font(.system(size: 24, weight: .bold))
            Text("Not a grade. Just what happened.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Card {
                statRow("Days you showed up", "\(showedUp) of 7")
                statRow("Things finished", "\(finished)")
                statRow("Routines completed", "\(routines)")
                statRow("Hours logged", "\(logged)")
                if let best, best.1 >= 2 {
                    HStack {
                        Text("Best streak").font(.system(size: 16))
                        Spacer()
                        Text(best.0.title).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                        StreakBadge(count: best.1, tint: accent)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                }
            }
            Text(finished == 0 ? "Rough week? That happens. Next week can start small." : "That counts. Take a second to notice it.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
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

    // MARK: 2. What kept slipping

    private var slipping: some View {
        let tasks = store.slippingTasks()
        let nextWeek = Day.add(7, to: store.weekStart())
        return VStack(alignment: .leading, spacing: 14) {
            Text("What kept slipping").font(.system(size: 24, weight: .bold))
            Text(tasks.isEmpty ? "Nothing’s been sliding. Nice." : "Decide once, so it stops nagging you.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            ForEach(tasks) { t in
                VStack(alignment: .leading, spacing: 10) {
                    Text(t.title).font(.system(size: 16, weight: .semibold))
                    Text(t.date < Day.today ? "Planned for " + Day.short(t.date) : "Pushed back \(store.data.pushes[t.id.uuidString] ?? 0) times")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        chip("Next week") { store.move(task: t.id, to: nextWeek) }
                        chip("Break it down") { composer = ComposerRequest(mode: .task, task: t) }
                        Spacer()
                        Button("Let go") { store.delete(task: t.id) }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.card2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 3. Goals

    private var planDays: [String] {
        let start = store.reviewTargetWeek()
        let today = Day.today
        return (0..<7).map { Day.add($0, to: start) }.filter { $0 >= today }
    }

    private var goalsStep: some View {
        let days = planDays
        let isNext = store.reviewTargetWeek() != store.weekStart()
        return VStack(alignment: .leading, spacing: 14) {
            Text("One step toward each goal").font(.system(size: 24, weight: .bold))
            Text("Small enough to actually do. It becomes a task on the day you pick" + (isNext ? " next week." : "."))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            ForEach(reviewGoals) { g in
                goalPlanner(g, days: days)
            }
            Text("Leave any blank to skip it this week.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func goalPlanner(_ g: Goal, days: [String]) -> some View {
        let planned = store.data.tasks.filter { $0.goalID == g.id && !$0.isRepeating && days.contains($0.date) && !$0.isDone(on: $0.date) }
        let chosenDay = goalDays[g.id] ?? days.first ?? Day.today
        return VStack(alignment: .leading, spacing: 10) {
            Text(g.title).font(.system(size: 17, weight: .semibold))
            Text(store.progressText(g)).font(.system(size: 13)).foregroundStyle(.secondary)
            if !planned.isEmpty {
                Text("Already planned: " + planned.map { $0.title + " (" + Day.shortWeekdays[Day.weekday($0.date) - 1] + ")" }.joined(separator: ", "))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            TextField("One step, e.g. 10 practice problems", text: Binding(
                get: { goalSteps[g.id] ?? "" },
                set: { goalSteps[g.id] = $0 }
            ), axis: .vertical)
                .font(.system(size: 16))
                .padding(12)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { d in
                        let on = d == chosenDay
                        Button {
                            goalDays[g.id] = d
                        } label: {
                            Text(Day.shortWeekdays[Day.weekday(d) - 1] + " \(Day.dayNumber(d))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(on ? Theme.onAccent(scheme == .dark) : .primary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(on ? accent : Theme.card2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func addGoalSteps() {
        let days = planDays
        for g in reviewGoals {
            let text = (goalSteps[g.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            store.addGoalStep(g, title: text, day: goalDays[g.id] ?? days.first ?? Day.today)
            addedSteps += 1
        }
        goalSteps = [:]
    }

    // MARK: 4. Focus

    private var focusStep: some View {
        let target = store.reviewTargetWeek()
        let isNext = target != store.weekStart()
        let open = store.data.tasks.filter { !$0.isRepeating && !$0.isDone(on: Day.today) }
        let suggestions = (open.filter { $0.goalID != nil } + open.filter { $0.goalID == nil })
            .map(\.title)
            .filter { !focuses.contains($0) }
            .prefix(6)
        return VStack(alignment: .leading, spacing: 14) {
            Text(isNext ? "What matters next week?" : "What matters this week?").font(.system(size: 24, weight: .bold))
            Text("Up to 3. They sit at the top of This week so you don’t lose them.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { i in
                TextField(i == 0 ? "The one that matters most" : "Another (optional)", text: $focuses[i], axis: .vertical)
                    .font(.system(size: 16))
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !suggestions.isEmpty {
                Text("From your tasks").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                FlowChips(items: Array(suggestions)) { title in
                    if let i = focuses.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        focuses[i] = title
                    }
                }
            }
        }
    }

    // MARK: 5. Done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Week set.").font(.system(size: 28, weight: .bold))
            Text(earned ? "+1 token for doing the review." : "Your focus is at the top of This week.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(earned ? accent : .secondary)
            if addedSteps > 0 {
                Text(addedSteps == 1 ? "1 goal step is on your calendar." : "\(addedSteps) goal steps are on your calendar.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            Text("You can redo it any time from This week.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: Flow

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing = store.data.reviews[store.reviewTargetWeek()] {
            for (i, f) in existing.focuses.prefix(3).enumerated() { focuses[i] = f }
        }
    }

    private func next() {
        switch step {
        case .lookBack: withAnimation { step = .slipping }
        case .slipping: withAnimation { step = reviewGoals.isEmpty ? .focus : .goals }
        case .goals:
            addGoalSteps()
            withAnimation { step = .focus }
        case .focus:
            earned = store.saveReview(focuses: focuses)
            withAnimation { step = .done }
        case .done: dismiss()
        }
    }
}

/// Simple wrapping row of tappable chips.
struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    tap(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        Text(item).font(.system(size: 14)).lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Theme.card2, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
