import SwiftUI

struct OptionsSheet: View {
    enum Action { case smaller, timer, notNow, pickOne, done, later(Date), skip }

    @EnvironmentObject var store: AppStore
    let item: NowItem
    let holdMode: Bool
    let run: (Action) -> Void
    @State private var showLater = false
    @State private var picking = false
    @State private var pickedTime = Date().addingTimeInterval(90 * 60)

    var body: some View {
        let smaller = store.isSmaller(item)
        let timing = store.timer?.itemID == item.id
        let pushes = store.pushes(item)
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Right now")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(store.displayTitle(item))
                        .font(.system(size: 17, weight: .semibold))
                    if pushes >= 2 {
                        Text("You’ve pushed this one \(pushes) times. Smaller might help.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent(store.settings.palette))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

                row(icon: "arrow.down.right.and.arrow.up.left",
                    title: smaller ? "Back to the full task" : "Make it smaller",
                    detail: smaller ? item.step.title : item.step.smallerOrDefault,
                    action: .smaller)
                row(icon: "timer",
                    title: timing ? "Stop the timer" : "Start a 5-minute timer",
                    detail: timing ? "Back to just the task" : "Just begin. Stop whenever.",
                    action: .timer)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showLater.toggle() }
                } label: {
                    rowLabel(icon: "clock.arrow.circlepath", title: "Later",
                             detail: "Off Now until a time you pick. It comes back on its own.",
                             trailing: showLater ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                if showLater { laterChoices }
                row(icon: "moon", title: "Not now", detail: "Let something else go first", action: .notNow)
                row(icon: "forward", title: item.kind == .routine ? "Skip this routine today" : "Skip it today",
                    detail: skipDetail, action: .skip)
                row(icon: "shuffle", title: "Pick one for me", detail: "Skip the deciding", action: .pickOne)
                if holdMode {
                    row(icon: "checkmark", title: "Mark it done", detail: "Skip the hold this time", action: .done)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 22)
        }
    }

    // MARK: Later

    private var laterChoices: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(choices) { c in
                Button {
                    run(.later(c.date))
                } label: {
                    HStack {
                        Text(c.label).font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text(Day.clock(c.date)).font(.system(size: 14).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { picking.toggle() }
            } label: {
                HStack {
                    Text("Pick a time").font(.system(size: 15, weight: .medium))
                    Spacer()
                    Image(systemName: picking ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if picking {
                DatePicker("Time", selection: $pickedTime, in: Date()..., displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                Button {
                    run(.later(pickedTime))
                } label: {
                    Text("Back at " + Day.clock(pickedTime))
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.accent(store.settings.palette), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
        .padding(.leading, 56)
        .transition(.opacity)
    }

    private struct LaterChoice: Identifiable {
        let label: String
        let date: Date
        var id: String { label }
    }

    private var choices: [LaterChoice] {
        let now = Date()
        var list = [
            LaterChoice(label: "In 30 minutes", date: now.addingTimeInterval(30 * 60)),
            LaterChoice(label: "In 1 hour", date: now.addingTimeInterval(60 * 60)),
            LaterChoice(label: "In 2 hours", date: now.addingTimeInterval(2 * 60 * 60)),
        ]
        let cal = Day.calendar
        if let six = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now), six.timeIntervalSince(now) > 2.5 * 3600 {
            list.append(LaterChoice(label: "This evening", date: six))
        }
        if let nine = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now), nine.timeIntervalSince(now) > 2.5 * 3600 {
            list.append(LaterChoice(label: "Tonight", date: nine))
        }
        return list
    }

    private var skipDetail: String {
        if item.kind == .routine { return "Missed it, or not today. It’s back next time." }
        if store.data.tasks.first(where: { $0.id == item.refID })?.isRepeating == true {
            return "Missed it, or not today. It’s back next time it’s due."
        }
        return "Not today. It’ll be back tomorrow."
    }

    // MARK: Rows

    private func row(icon: String, title: String, detail: String, action: Action) -> some View {
        Button {
            run(action)
        } label: {
            rowLabel(icon: icon, title: title, detail: detail)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(icon: String, title: String, detail: String, trailing: String? = nil) -> some View {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let trailing {
                    Image(systemName: trailing)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
    }
}
