import SwiftUI

/// The day as a flowchart, drawn straight onto Now over the orb.
/// Pull down: the task slides down and what's coming appears above it, nearest step first.
/// Pull up: the task slides up and what's done today appears below it, crossed out.
struct DayFlowColumn: View {
    enum Kind { case upcoming, done }

    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    let kind: Kind
    let maxRows: Int

    private var dark: Bool { scheme == .dark }
    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        let entries = kind == .upcoming ? upcomingEntries() : doneEntries()
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                Text(kind == .upcoming ? "Nothing else planned today." : "Nothing finished yet today.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.orbSub(dark))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { pair in
                row(pair.element,
                    isFirst: kind == .upcoming ? pair.offset == 0 : false,
                    isLast: kind == .upcoming ? false : pair.offset == entries.count - 1)
            }
        }
        .frame(maxWidth: 330)
        .shadow(color: dark ? .black.opacity(0.55) : .white.opacity(0.75), radius: 10)
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ e: FlowEntry, isFirst: Bool, isLast: Bool) -> some View {
        let line = dark ? Color.white.opacity(0.28) : Color.black.opacity(0.22)
        FlowRow(isFirst: isFirst, isLast: isLast, lineColor: line) {
            node(e)
        } content: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title)
                        .font(.system(size: e.isHeader ? 14 : 16, weight: e.isHeader ? .semibold : .regular))
                        .strikethrough(e.done)
                        .foregroundStyle(e.done || e.dimmed ? Theme.orbSub(dark) : Color.primary)
                        .lineLimit(2)
                    if let meta = e.meta {
                        Text(meta)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.orbSub(dark))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let id = e.startRoutine {
                    Button("Start") { store.cueHappened(routineID: id, announce: false) }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Start " + e.title)
                }
                if let key = e.restoreKey {
                    Button(e.restoreLabel) { withAnimation { store.bringBack(key) } }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.borderless)
                        .accessibilityLabel(e.restoreLabel + " " + e.title)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func node(_ e: FlowEntry) -> some View {
        if e.isMore {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.orbSub(dark))
        } else if e.isHeader {
            Image(systemName: e.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(e.dimmed ? Theme.orbSub(dark) : accent)
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else if e.done {
            ZStack {
                Circle().fill(Theme.orbSub(dark).opacity(0.8)).frame(width: 16, height: 16)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(dark ? Color.black : Color.white)
            }
        } else {
            Circle()
                .strokeBorder(e.color, lineWidth: 2)
                .background(Circle().fill(.ultraThinMaterial))
                .frame(width: 14, height: 14)
                .opacity(e.dimmed ? 0.6 : 1)
        }
    }

    // MARK: Building the flow

    /// Coming up, nearest first, then reversed so the nearest sits just above the task.
    private func upcomingEntries() -> [FlowEntry] {
        var list: [FlowEntry] = []
        let due = store.queue()
        let later = store.laterToday()
        for (i, item) in (due + later).enumerated() {
            // The first due step is the big text on Now; everything else gets a header.
            let isCurrent = i == 0 && !due.isEmpty
            let at = i >= due.count ? store.startsAt(item) : nil
            let snoozed = i >= due.count && store.snoozedUntil(item) != nil
            let steps: [Step]
            var header: String = item.triggerLabel
            var symbol = "checkmark.circle"
            var cue: String? = nil
            if item.kind == .routine, let r = store.data.routines.first(where: { $0.id == item.refID }) {
                steps = r.steps
                header = r.title
                cue = r.hasName ? r.trigger.label : nil
                symbol = r.trigger.kind.symbol
            } else if let t = store.data.tasks.first(where: { $0.id == item.refID }) {
                steps = t.steps
                if header == "Today" { header = "Task" }
            } else {
                continue
            }
            let from = isCurrent ? item.stepIndex + 1 : item.stepIndex
            if !isCurrent {
                let progress: String? = item.stepCount > 1 ? "\(item.stepIndex + 1) of \(item.stepCount)" : nil
                let when = at.map { (snoozed ? "Snoozed until " : "At ") + $0 }
                let meta = [when, cue, progress].compactMap { $0 }.joined(separator: " · ")
                if item.kind == .task, at != nil { header = "Task" }
                list.append(FlowEntry(id: "h-" + item.baseKey, title: header, meta: meta.isEmpty ? nil : meta, symbol: symbol,
                                      isHeader: true, restoreKey: snoozed ? item.baseKey : nil))
            }
            if from < steps.count {
                for j in from..<steps.count {
                    let s = steps[j]
                    list.append(FlowEntry(id: item.baseKey + "#" + String(j), title: s.title, meta: meta(s),
                                          color: store.type(s.typeID).color))
                }
            }
        }
        for r in store.cueRoutinesNotStarted() {
            var detail = r.trigger.windowLabel ?? "Waiting"
            if r.trigger.kind == .place && r.trigger.place != nil { detail += " · on arrival" }
            let canStart = r.trigger.inWindow()
            if r.hasName { detail = r.trigger.label + " · " + detail }
            list.append(FlowEntry(id: "w-" + r.id.uuidString, title: r.hasName ? r.title : r.trigger.label, meta: detail, symbol: r.trigger.kind.symbol,
                                  isHeader: true, dimmed: true, startRoutine: canStart ? r.id : nil))
            for (j, s) in r.steps.enumerated() {
                list.append(FlowEntry(id: "w-" + r.id.uuidString + "#" + String(j), title: s.title, meta: meta(s),
                                      color: store.type(s.typeID).color, dimmed: true))
            }
        }
        for s in store.skippedToday() {
            list.append(FlowEntry(id: "s-" + s.key, title: s.title, meta: "Skipped today", symbol: "forward",
                                  isHeader: true, dimmed: true, restoreKey: s.key, restoreLabel: "Undo"))
        }
        if list.count > maxRows && maxRows > 1 {
            let hidden = list.count - (maxRows - 1)
            list = Array(list.prefix(maxRows - 1))
            list.append(FlowEntry(id: "more-later", title: "+\(hidden) more later", isMore: true))
        }
        return list.reversed()
    }

    /// Done today, most recent first, right under the task.
    private func doneEntries() -> [FlowEntry] {
        // One line per task or routine, however many of its steps were done.
        let runs = store.runs(on: Day.today).sorted { $0.at > $1.at }
        var list: [FlowEntry] = runs.map { r in
            var parts: [String] = [Day.clock(r.at), r.isRoutine ? "Routine" : store.type(r.typeID).name]
            if let steps = r.stepsText { parts.append(steps) }
            if r.earnedToken { parts.append("+1 token") }
            return FlowEntry(id: r.id, title: r.title, meta: parts.joined(separator: " · "),
                             color: store.type(r.typeID).color, done: r.finished, dimmed: !r.finished)
        }
        if list.count > maxRows && maxRows > 1 {
            let hidden = list.count - (maxRows - 1)
            list = Array(list.prefix(maxRows - 1))
            list.append(FlowEntry(id: "more-earlier", title: "+\(hidden) earlier", isMore: true))
        }
        return list
    }

    private func meta(_ s: Step) -> String {
        var parts: [String] = [store.type(s.typeID).name]
        if let l = s.limitText { parts.append(l) }
        return parts.joined(separator: " · ")
    }
}

struct FlowEntry: Identifiable {
    let id: String
    var title: String
    var meta: String? = nil
    var symbol: String = "circle"
    var color: Color = .gray
    var isHeader = false
    var isMore = false
    var done = false
    var dimmed = false
    var startRoutine: UUID? = nil
    /// A snoozed or skipped item: tapping brings it back.
    var restoreKey: String? = nil
    var restoreLabel: String = "Bring back"
}

/// A row of the flowchart: a node on a vertical line, and content beside it.
struct FlowRow<Node: View, Content: View>: View {
    let isFirst: Bool
    let isLast: Bool
    let lineColor: Color
    @ViewBuilder var node: () -> Node
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle().fill(isFirst ? Color.clear : lineColor).frame(width: 2)
                    Rectangle().fill(isLast ? Color.clear : lineColor).frame(width: 2)
                }
                node()
            }
            .frame(width: 28)
            content()
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
