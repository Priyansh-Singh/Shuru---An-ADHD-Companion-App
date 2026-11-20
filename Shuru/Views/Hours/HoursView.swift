import SwiftUI
import UIKit

private struct LoggedHour: Identifiable {
    let hour: Int
    let entry: HourEntry
    var id: Int { hour }
}

/// Externalise time: watch the day pass in blocks, and log what each hour went to.
struct HoursView: View {
    @EnvironmentObject var store: AppStore
    @State private var note = ""
    @State private var toast: String?
    @FocusState private var noteFocused: Bool

    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .animation(.easeOut(duration: 0.25), value: toast)
    }

    private func content(now: Date) -> some View {
        let s = store.settings
        let today = Day.today
        let hour = Day.calendar.component(.hour, from: now)
        let wake = s.wakeHour
        let bed = max(s.bedHour, wake + 1)
        let pending = pendingHours(now: now, today: today, wake: wake)
        return ZStack(alignment: .bottom) {
            PageScroll {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Day.clock(now))
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .tracking(-0.8)
                    Text(sinceLine(now: now))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    if let log = store.activeLog, let item = store.queue().first(where: { $0.id == log.itemID }) {
                        Text("Logging now: " + item.step.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)

                dayCard(today: today, hour: hour, wake: wake, bed: bed)

                checkInCard(pending: pending)

                loggedCard(today: today, wake: wake, bed: bed)

                if s.checkEvery > 0 && s.chime != .off {
                    Text("You’ll get a nudge every " + (s.checkEvery == 1 ? "hour" : "\(s.checkEvery) hours") + " between " + Day.hourLabel(wake) + " and " + Day.hourLabel(bed) + ". Change it in Settings.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            if let toast {
                Toast(text: toast).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Pieces

    private func dayCard(today: String, hour: Int, wake: Int, bed: Int) -> some View {
        let hours = Array(wake..<bed)
        let left = max(0, bed - hour - 1)
        let unlogged = hours.filter { $0 <= hour && store.entry(day: today, hour: $0) == nil }.count
        return Card(padding: EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16)) {
            HStack {
                Text("Your day").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(left) h left").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            HStack(spacing: 3) {
                ForEach(hours, id: \.self) { h in
                    HourBlock(entry: store.entry(day: today, hour: h), isPast: h < hour, isNow: h == hour,
                              color: store.entry(day: today, hour: h).map { store.type($0.typeID).color } ?? .clear,
                              accent: accent)
                        .accessibilityLabel(Day.hourLabel(h) + ": " + (store.entry(day: today, hour: h).map { store.type($0.typeID).name } ?? (h <= hour ? "not logged" : "later")))
                }
            }
            .frame(height: 30)
            HStack {
                Text(Day.hourLabel(wake))
                Spacer()
                Text(unlogged > 0 ? "\(unlogged) not logged" : "All caught up")
                Spacer()
                Text(Day.hourLabel(bed))
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    private func checkInCard(pending: [Int]) -> some View {
        let title: String
        if let first = pending.first, let last = pending.last {
            title = first == last
                ? "What is " + Day.hourLabel(first) + " going to?"
                : "What did " + Day.hourLabel(first) + "–" + Day.hourLabel(last + 1) + " go to?"
        } else {
            title = "You’re all caught up"
        }
        return Card(padding: EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16)) {
            Text(title).font(.system(size: 16, weight: .semibold)).frame(minHeight: 44)
            if !pending.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(store.data.types) { t in
                        Button {
                            logPending(pending, typeID: t.id, label: t.name)
                        } label: {
                            HStack(spacing: 8) {
                                TypeDot(color: t.color)
                                Text(t.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        logPending(pending, typeID: TaskType.unknownID, label: "Don’t remember")
                    } label: {
                        Text("Don’t remember")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                TextField("Add a note (optional)", text: $note)
                    .font(.system(size: 15))
                    .focused($noteFocused)
                    .padding(.top, 10)
            }
        }
    }

    private func loggedCard(today: String, wake: Int, bed: Int) -> some View {
        let logged: [LoggedHour] = (0..<24).compactMap { h in
            guard let e = store.entry(day: today, hour: h) else { return nil }
            return LoggedHour(hour: h, entry: e)
        }
        return Card {
            CardHeader("Logged today")
            if logged.isEmpty {
                Text("Nothing yet. Pick what this hour is going to above.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            ForEach(logged) { pair in
                let type = store.type(pair.entry.typeID)
                HStack(spacing: 12) {
                    TypeDot(color: type.color).frame(width: 20)
                    Text(type.name + (pair.entry.note.isEmpty ? "" : " · " + pair.entry.note))
                        .font(.system(size: 16))
                        .lineLimit(1)
                    Spacer()
                    Text((pair.entry.auto ? "Auto · " : "") + Day.hourLabel(pair.hour))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
            }
        }
    }

    // MARK: Logic

    private func pendingHours(now: Date, today: String, wake: Int) -> [Int] {
        let hour = Day.calendar.component(.hour, from: now)
        guard hour >= wake else { return [] }
        var start = wake
        if let last = store.data.lastCheckIn, Day.key(last) == today {
            start = max(wake, Day.calendar.component(.hour, from: last))
        }
        return (start...hour).filter { store.entry(day: today, hour: $0) == nil }
    }

    private func sinceLine(now: Date) -> String {
        guard let last = store.data.lastCheckIn else { return "No check-ins yet" }
        let mins = Int(now.timeIntervalSince(last) / 60)
        if mins < 1 { return "You just checked in." }
        if mins < 60 { return "\(mins) min since your last check-in" }
        let h = mins / 60, m = mins % 60
        return "\(h) h" + (m > 0 ? " \(m) min" : "") + " since your last check-in"
    }

    private func logPending(_ hours: [Int], typeID: String, label: String) {
        store.log(hours: hours, typeID: typeID, note: note.trimmingCharacters(in: .whitespaces))
        note = ""
        noteFocused = false
        if store.settings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        let text = "Logged as " + label
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toast == text { toast = nil }
        }
    }
}

struct HourBlock: View {
    let entry: HourEntry?
    let isPast: Bool
    let isNow: Bool
    let color: Color
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .overlay {
                if entry == nil && (isPast || isNow) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isNow ? accent : Theme.checkbox, style: StrokeStyle(lineWidth: 1.2, dash: isNow ? [] : [3, 2]))
                }
            }
            .frame(maxWidth: .infinity)
    }

    private var fill: Color {
        if entry != nil { return color }
        if isPast || isNow { return .clear }
        return Theme.card2
    }
}
