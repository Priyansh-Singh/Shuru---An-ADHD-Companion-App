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
    @State private var editing: HourEditRequest?
    @FocusState private var noteFocused: Bool

    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .animation(.easeOut(duration: 0.25), value: toast)
        .sheet(item: $editing) { req in
            HourEditor(hour: req.hour)
                .presentationDetents([.medium, .large])
        }
    }

    private func content(now: Date) -> some View {
        let s = store.settings
        let today = Day.today
        let hour = Day.calendar.component(.hour, from: now)
        let wake = s.wakeHour
        let bed = max(s.bedHour, wake + 1)
        let pending = pendingHours(now: now, today: today, wake: wake)
        let nudge: String? = (s.checkEvery > 0 && s.chime != .off) ? nudgeText(every: s.checkEvery, wake: wake, bed: bed) : nil
        return ZStack(alignment: .bottom) {
            PageScroll {
                header(now: now)

                dayCard(today: today, hour: hour, wake: wake, bed: bed)

                checkInCard(pending: pending)

                loggedCard(today: today, wake: wake, bed: bed)

                if let nudge {
                    Text(nudge)
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

    private func header(now: Date) -> some View {
        let logging: String? = activeTitle()
        return VStack(alignment: .leading, spacing: 4) {
            Text(Day.clock(now))
                .font(.system(size: 40, weight: .bold).monospacedDigit())
                .tracking(-0.8)
            Text(sinceLine(now: now))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            if let logging {
                Text("Logging now: \(logging)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func activeTitle() -> String? {
        guard let log = store.activeLog else { return nil }
        return store.queue().first(where: { $0.id == log.itemID })?.step.title
    }

    private func nudgeText(every: Int, wake: Int, bed: Int) -> String {
        let span = every == 1 ? "hour" : "\(every) hours"
        return "You’ll get a nudge every \(span) between \(Day.hourLabel(wake)) and \(Day.hourLabel(bed)). Change it in Settings."
    }

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
                    Button {
                        editing = HourEditRequest(hour: h)
                    } label: {
                        HourBlock(entry: store.entry(day: today, hour: h), isPast: h < hour, isNow: h == hour,
                                  color: store.entry(day: today, hour: h).map { store.type($0.typeID).color } ?? .clear,
                                  accent: accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Day.hourLabel(h) + ": " + (store.entry(day: today, hour: h).map { store.type($0.typeID).name } ?? (h <= hour ? "not logged" : "later")))
                    .accessibilityHint("Log or change this hour")
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
                TextField("What happened? (optional)", text: $note, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .focused($noteFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.bottom, 10)
                Text("Then pick what it was:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
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
            }
        }
    }

    private func loggedCard(today: String, wake: Int, bed: Int) -> some View {
        let logged: [LoggedHour] = (0..<24).compactMap { h in
            guard let e = store.entry(day: today, hour: h) else { return nil }
            return LoggedHour(hour: h, entry: e)
        }
        return Card {
            CardHeader("Logged today") {
                Button {
                    editing = HourEditRequest(hour: Day.calendar.component(.hour, from: Date()))
                } label: {
                    Label("Log an hour", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
            }
            if logged.isEmpty {
                Text("Nothing yet. Tap an hour in Your day, or Log an hour.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            ForEach(logged) { pair in
                LoggedHourRow(hour: pair.hour, entry: pair.entry, type: store.type(pair.entry.typeID)) {
                    editing = HourEditRequest(hour: pair.hour)
                }
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

/// One logged hour: what happened first, the type underneath.
/// Tap to edit it; the arrow shows all of a long note.
struct LoggedHourRow: View {
    let hour: Int
    let entry: HourEntry
    let type: TaskType
    let edit: () -> Void
    @State private var expanded = false

    private var mainText: String { entry.note.isEmpty ? type.name : entry.note }
    private var isLong: Bool { mainText.count > 38 }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: edit) {
                HStack(alignment: .top, spacing: 12) {
                    Text(Day.hourLabel(hour))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mainText)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .lineLimit(expanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            TypeDot(color: type.color, size: 7)
                            Text(type.name + (entry.auto ? " · logged automatically" : ""))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double tap to edit")

            if isLong {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Show less" : "Show all")
            } else {
                Color.clear.frame(width: 16, height: 1)
            }
        }
    }
}

struct HourEditRequest: Identifiable {
    let hour: Int
    var id: Int { hour }
}

/// Log or fix any hour of today by hand.
struct HourEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var hour: Int
    @State private var typeID: String?
    @State private var note = ""
    @State private var loaded = false
    private let original: Int

    init(hour: Int) {
        _hour = State(initialValue: hour)
        original = hour
    }

    var body: some View {
        let existing = store.entry(day: Day.today, hour: original)
        NavigationStack {
            Form {
                Picker("Hour", selection: $hour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(Day.hourLabel(h) + "–" + Day.hourLabel(h + 1)).tag(h)
                    }
                }
                Section("What happened") {
                    TextField("e.g. Went down a YouTube hole, then cooked", text: $note, axis: .vertical)
                        .lineLimit(2...8)
                }
                Section("Type") {
                    ForEach(store.data.types + [store.type(TaskType.unknownID)]) { t in
                        Button {
                            typeID = t.id
                        } label: {
                            HStack {
                                TypeDot(color: t.color, size: 10)
                                Text(t.name).foregroundStyle(.primary)
                                Spacer()
                                if typeID == t.id {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent(store.settings.palette))
                                }
                            }
                        }
                        .accessibilityAddTraits(typeID == t.id ? .isSelected : [])
                    }
                }
                if existing != nil {
                    Section {
                        Button("Clear this hour", role: .destructive) {
                            store.clearHour(original)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Log an hour" : "Edit hour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let typeID else { return }
                        if hour != original && existing != nil { store.clearHour(original) }
                        store.setHour(hour, typeID: typeID, note: note)
                        dismiss()
                    }
                    .disabled(typeID == nil)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing {
                typeID = e.typeID
                note = e.note
            }
        }
    }
}
