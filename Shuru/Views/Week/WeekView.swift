import SwiftUI

/// No streaks to break. Just a look back, and tokens to spend.
struct WeekView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing = false
    @State private var newReward = ""
    @State private var newCost = 5
    @State private var toast: String?
    @State private var undoRewards: [Reward]?
    @State private var reviewing = false
    @FocusState private var rewardFocused: Bool

    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        let first = store.weekStart()
        let week = (0..<7).map { Day.add($0, to: first) }
        let done = store.data.completions.filter { week.contains($0.day) }
        ZStack(alignment: .bottom) {
            PageScroll {
                ScreenHeader(title: "This week", subtitle: "A look back, and what matters next.")
                reviewCard
                goalsCard
                if store.settings.tokens { tokensCard }
                showedUpCard(week: week)
                routinesCard(done: done)
                guessesCard
                totalsCard(done: done)
            }
            if let toast {
                Toast(text: toast, actionLabel: undoRewards == nil ? nil : "Undo") {
                    if let undo = undoRewards { store.data.rewards = undo }
                    undoRewards = nil
                    self.toast = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: toast)
        .onAppear { store.normalizeTokens() }
        .sheet(isPresented: $reviewing) {
            WeeklyReviewView()
        }
    }

    // MARK: Tokens

    private var tokensCard: some View {
        let s = store.settings
        let balance = store.data.tokens
        let earned = store.tokensEarnedToday
        return Card(padding: EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0)) {
            CardHeader("Tokens") {
                Button(editing ? "Done" : "Edit") { withAnimation { editing.toggle() } }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(balance)").font(.system(size: 22, weight: .bold).monospacedDigit()).foregroundStyle(accent)
                Text("to spend · " + (s.tokenCap > 0 ? "\(earned) of \(s.tokenCap) earned today" : "\(earned) earned today"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            Text("1 for each task or routine you finish. Breaking it into steps doesn’t change that, so split things up as much as helps.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
            if s.tokenWeekly {
                Label(resetNote(balance: balance), systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            ForEach(store.data.rewards) { r in
                rewardRow(r, balance: balance)
            }
            if store.data.rewards.isEmpty {
                Text("No rewards yet. Add something you’d actually look forward to.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            HStack(spacing: 6) {
                Button {
                    addReward()
                } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(accent).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add reward")
                TextField("Add your own reward", text: $newReward)
                    .font(.system(size: 16))
                    .focused($rewardFocused)
                    .submitLabel(.done)
                    .onSubmit(addReward)
                Stepper(value: $newCost, in: 1...99) {
                    Text("\(newCost)").font(.system(size: 15, weight: .semibold).monospacedDigit())
                }
                .fixedSize()
                .accessibilityLabel("Cost: \(newCost) tokens")
            }
            .padding(.leading, 2)
            .padding(.trailing, 12)
            .frame(minHeight: 48)
        }
    }

    @ViewBuilder
    private func rewardRow(_ r: Reward, balance: Int) -> some View {
        let can = balance >= r.cost
        HStack(spacing: 8) {
            if editing {
                Button {
                    remove(r)
                } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.danger).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove " + r.label)
            }
            Text(r.label).font(.system(size: 16)).lineLimit(1)
            Spacer(minLength: 8)
            if editing {
                Stepper(value: Binding(get: { r.cost }, set: { v in
                    if let i = store.data.rewards.firstIndex(where: { $0.id == r.id }) { store.data.rewards[i].cost = v }
                }), in: 1...99) {
                    Text("\(r.cost)").font(.system(size: 15, weight: .semibold).monospacedDigit())
                }
                .fixedSize()
                .accessibilityLabel("Cost of \(r.label): \(r.cost) tokens")
            } else {
                Button(can ? "Spend \(r.cost)" : "\(r.cost) tokens") {
                    if store.spend(r) { show("Enjoy it. You earned that.") }
                }
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(can ? accent : .secondary)
                .disabled(!can)
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
                .accessibilityLabel(can ? "Spend \(r.cost) tokens on \(r.label)" : "\(r.label): costs \(r.cost), you need \(r.cost - balance) more")
            }
        }
        .padding(.leading, editing ? 4 : 16)
        .padding(.trailing, 8)
        .frame(minHeight: 48)
    }

    private func resetNote(balance: Int) -> String {
        let wd = Day.calendar.component(.weekday, from: Date())
        let days = (9 - wd) % 7 == 0 ? 7 : (9 - wd) % 7
        let when = days == 1 ? "tomorrow" : (days == 7 ? "next Monday" : "on Monday, in \(days) days")
        if balance > 0 {
            return "Your \(balance) unspent " + (balance == 1 ? "token clears " : "tokens clear ") + when + "."
        }
        return "Tokens clear " + when + "."
    }

    private func addReward() {
        let label = newReward.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        store.data.rewards.append(Reward(label: label, cost: newCost))
        newReward = ""
        newCost = 5
    }

    private func remove(_ r: Reward) {
        let before = store.data.rewards
        store.data.rewards.removeAll { $0.id == r.id }
        let name = r.label.count > 22 ? String(r.label.prefix(21)) + "…" : r.label
        undoRewards = before
        show("Removed “\(name)”", keepUndo: true)
    }

    private func show(_ text: String, keepUndo: Bool = false) {
        if !keepUndo { undoRewards = nil }
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + (keepUndo ? 4 : 2.2)) {
            if toast == text {
                toast = nil
                undoRewards = nil
            }
        }
    }

    // MARK: The week

    private func showedUpCard(week: [String]) -> some View {
        let today = Day.today
        let shown = week.filter { !store.completions(on: $0).isEmpty }.count
        return Card(padding: EdgeInsets(top: 4, leading: 0, bottom: 14, trailing: 0)) {
            CardHeader("Showed up") {
                Text("\(shown) of \(week.filter { $0 <= today }.count) days").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack {
                ForEach(week, id: \.self) { d in
                    let did = !store.completions(on: d).isEmpty
                    let future = d > today
                    VStack(spacing: 6) {
                        Circle()
                            .strokeBorder(did ? accent : Theme.checkbox, style: StrokeStyle(lineWidth: 1.5, dash: did || future ? [] : [3, 3]))
                            .background(Circle().fill(did ? accent : Color.clear))
                            .frame(width: 30, height: 30)
                            .opacity(future ? 0.35 : 1)
                        Text(Day.letters[Day.weekday(d) - 1]).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Day.longWeekdays[Day.weekday(d) - 1] + (did ? ": showed up" : (future ? ": coming up" : ": rest day")))
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func totalsCard(done: [Completion]) -> some View {
        let wholes = done.filter { $0.finishedWhole }
        let routines = wholes.filter { $0.isRoutine }.count
        let steps = done.count
        var byType: [String: Int] = [:]
        for c in done { byType[c.typeID, default: 0] += 1 }
        let top = byType.sorted { $0.value > $1.value }.prefix(3)
        return Card {
            CardHeader("Totals")
            totalRow("Things finished", "\(wholes.count)")
            totalRow("Steps done", "\(steps)")
            totalRow("Routines completed", "\(routines)")
            if !top.isEmpty {
                totalRow("Most time on", top.map { store.type($0.key).name }.joined(separator: ", "))
            }
        }
    }

    private func totalRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 16))
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    // MARK: Routines and streaks

    private struct RoutineStat: Identifiable {
        let routine: Routine
        let streak: Int
        let done: Int
        let scheduled: Int
        var id: UUID { routine.id }
    }

    private func routinesCard(done: [Completion]) -> some View {
        let stats: [RoutineStat] = store.data.routines.filter { $0.enabled }.map { r in
            let w = store.weekProgress(r)
            return RoutineStat(routine: r, streak: store.streak(r), done: w.done, scheduled: w.scheduled)
        }
        .filter { $0.scheduled > 0 || $0.streak > 0 }
        .sorted { ($0.streak, $0.done) > ($1.streak, $1.done) }
        return Card {
            CardHeader("Routines")
            if stats.isEmpty {
                Text("Routines that run this week show up here, with how often you kept up.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            ForEach(stats) { st in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.routine.title).font(.system(size: 16))
                        Text("\(st.done) of \(st.scheduled) this week")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if st.streak >= 2 {
                        StreakBadge(count: st.streak, tint: accent)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Time guesses

    private var guessesCard: some View {
        let start = store.weekStart()
        let timed = store.data.completions
            .filter { $0.day >= Day.add(-7, to: start) && $0.seconds != nil && $0.guessMinutes != nil }
            .sorted { $0.at > $1.at }
        let ratios: [Double] = timed.compactMap { c in
            guard let s = c.seconds, let g = c.guessMinutes, g > 0 else { return nil }
            return Double(s) / Double(g * 60)
        }
        let avg = ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count)
        return Card {
            CardHeader("Time guesses")
            if timed.isEmpty {
                Text("Give a step a time limit and finish it on Now. Shuru compares the limit you set with how long it really took.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                Text(guessSummary(avg))
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                ForEach(timed.prefix(5)) { c in
                    let took = Int(((Double(c.seconds ?? 0)) / 60).rounded())
                    let guess = c.guessMinutes ?? 0
                    HStack {
                        Text(c.title).font(.system(size: 15)).lineLimit(1)
                        Spacer()
                        Text("limit " + Step.duration(guess) + " · took " + Step.duration(max(1, took)))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(took > guess ? accent : .secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                }
            }
        }
    }

    private func guessSummary(_ ratio: Double) -> String {
        if ratio == 0 { return "" }
        if ratio > 1.15 { return String(format: "You usually take %.1f× the time you set.", ratio) }
        if ratio < 0.6 { return "You usually finish well inside your limits." }
        return "Your limits are close to how long things really take."
    }

    // MARK: Weekly review

    @ViewBuilder
    private var goalsCard: some View {
        let month = Day.monthKey(Day.today)
        let goals = store.goals(in: month)
        if !goals.isEmpty {
            Card {
                CardHeader(Day.monthName(month) + " goals") {
                    Button(store.monthIsEnding ? "Month review" : "Month so far") {
                        store.monthReview = MonthReviewRequest(month: month)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
                }
                ForEach(goals) { g in
                    GoalRow(goal: g, accent: accent) { store.monthReview = MonthReviewRequest(month: month) }
                }
            }
        }
    }

    @ViewBuilder
    private var reviewCard: some View {
        if let focus = store.currentFocus() {
            Card {
                CardHeader(focus.week == store.weekStart() ? "This week’s focus" : "Next week’s focus") {
                    Button("Redo") { reviewing = true }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 8)
                }
                ForEach(Array(focus.review.focuses.enumerated()), id: \.offset) { pair in
                    let isDone = pair.offset < focus.review.focusDone.count && focus.review.focusDone[pair.offset]
                    Button {
                        store.toggleFocus(week: focus.week, index: pair.offset)
                    } label: {
                        HStack(spacing: 12) {
                            CheckCircle(done: isDone, tint: accent).frame(width: 44)
                            Text(pair.element)
                                .font(.system(size: 16))
                                .strikethrough(isDone)
                                .foregroundStyle(isDone ? .secondary : .primary)
                            Spacer()
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                }
            }
        } else {
            Button {
                reviewing = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 20))
                        .foregroundStyle(accent)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly review").font(.system(size: 16, weight: .semibold))
                        Text("5 minutes: look back, clear what’s slipping, pick what matters next.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

}

struct StreakBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.system(size: 12))
            Text("\(count) in a row").font(.system(size: 13, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) in a row")
    }
}
