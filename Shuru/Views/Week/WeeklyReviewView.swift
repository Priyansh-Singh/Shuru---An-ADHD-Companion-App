import SwiftUI

/// Five minutes: look back, clear what's slipping, pick up to 3 things that matter next.
struct WeeklyReviewView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    enum ReviewStep: Int, CaseIterable { case lookBack, slipping, focus, done }

    @Environment(\.colorScheme) private var scheme
    @State private var step: ReviewStep = .lookBack
    @State private var focuses: [String] = ["", "", ""]
    @State private var earned = false
    @State private var composer: ComposerRequest?
    @State private var loaded = false

    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    progressDots
                    switch step {
                    case .lookBack: lookBack
                    case .slipping: slipping
                    case .focus: focusStep
                    case .done: doneStep
                    }
                }
                .padding(20)
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

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(ReviewStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? accent : Theme.checkbox.opacity(0.4))
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

    // MARK: 3. Focus

    private var focusStep: some View {
        let target = store.reviewTargetWeek()
        let isNext = target != store.weekStart()
        let suggestions = store.data.tasks
            .filter { !$0.isRepeating && !$0.isDone(on: Day.today) }
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

    // MARK: 4. Done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Week set.").font(.system(size: 28, weight: .bold))
            Text(earned ? "+1 token for doing the review." : "Your focus is at the top of This week.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(earned ? accent : .secondary)
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
        case .slipping: withAnimation { step = .focus }
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
