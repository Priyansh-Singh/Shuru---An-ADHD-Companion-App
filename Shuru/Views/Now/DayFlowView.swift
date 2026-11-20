import SwiftUI

/// Pull down on Now: what's coming, as a flow of routines and their steps, with tasks in line.
/// Pull up on Now: what's done today, crossed out.
struct DayFlowPanel: View {
    enum Kind { case upcoming, done }

    @EnvironmentObject var store: AppStore
    let kind: Kind
    let close: () -> Void

    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        VStack(spacing: 0) {
            if kind == .done { grabber }
            HStack {
                Text(kind == .upcoming ? "Coming up" : "Done today")
                    .font(.system(size: 20, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close", action: close)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, kind == .upcoming ? 8 : 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if kind == .upcoming { upcoming } else { done }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            if kind == .upcoming { grabber }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 24, y: kind == .upcoming ? 10 : -10)
        .padding(.horizontal, 8)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10).onEnded { v in
                    let dy = v.translation.height
                    if (kind == .upcoming && dy < -40) || (kind == .done && dy > 40) { close() }
                }
            )
            .accessibilityHidden(true)
    }

    // MARK: Coming up

    @ViewBuilder
    private var upcoming: some View {
        let blocks = upcomingBlocks()
        let waiting = store.cueRoutinesNotStarted()
        if blocks.isEmpty && waiting.isEmpty {
            Text("Nothing else planned today.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
        }
        ForEach(Array(blocks.enumerated()), id: \.element.id) { i, block in
            FlowBlockView(block: block, accent: accent, isFirstBlock: i == 0,
                          isLastBlock: i == blocks.count - 1 && waiting.isEmpty)
        }
        if !waiting.isEmpty {
            Text("Waiting for a cue")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(Array(waiting.enumerated()), id: \.element.id) { i, r in
                FlowBlockView(block: waitingBlock(r), accent: accent, isFirstBlock: i == 0, isLastBlock: i == waiting.count - 1,
                              dimmed: true) {
                    store.cueHappened(routineID: r.id, announce: false)
                }
            }
        }
    }

    private func upcomingBlocks() -> [FlowBlock] {
        let queue = store.queue()
        return queue.enumerated().compactMap { (pair: EnumeratedSequence<[NowItem]>.Element) -> FlowBlock? in
            let i = pair.offset
            let item = pair.element
            let steps: [Step]
            let header: String
            let symbol: String
            if item.kind == .routine, let r = store.data.routines.first(where: { $0.id == item.refID }) {
                steps = Array(r.steps.dropFirst(item.stepIndex))
                header = r.trigger.label
                symbol = r.trigger.kind.symbol
            } else if let t = store.data.tasks.first(where: { $0.id == item.refID }) {
                steps = Array(t.steps.dropFirst(item.stepIndex))
                header = item.triggerLabel == "Today" ? "Task" : item.triggerLabel
                symbol = "checkmark.circle"
            } else {
                return nil
            }
            let nodes: [FlowNode] = steps.enumerated().map { (p: EnumeratedSequence<[Step]>.Element) -> FlowNode in
                let j = p.offset, s = p.element
                return FlowNode(id: item.baseKey + "#" + String(item.stepIndex + j),
                         title: (i == 0 && j == 0) ? store.displayTitle(item) : s.title,
                         meta: nodeMeta(s),
                         color: store.type(s.typeID).color,
                         isCurrent: i == 0 && j == 0,
                         done: false)
            }
            let progress = item.stepCount > 1 ? "\(item.stepIndex + 1) of \(item.stepCount)" : nil
            return FlowBlock(id: item.baseKey, header: header, symbol: symbol, detail: progress, nodes: nodes)
        }
    }

    private func waitingBlock(_ r: Routine) -> FlowBlock {
        var detail = r.trigger.windowLabel ?? ""
        if r.trigger.kind == .place && r.trigger.place != nil {
            detail += detail.isEmpty ? "Starts when you arrive" : " · on arrival"
        }
        let nodes: [FlowNode] = r.steps.enumerated().map { (p: EnumeratedSequence<[Step]>.Element) -> FlowNode in
            let j = p.offset, s = p.element
            return FlowNode(id: r.id.uuidString + "#" + String(j), title: s.title, meta: nodeMeta(s),
                     color: store.type(s.typeID).color, isCurrent: false, done: false)
        }
        return FlowBlock(id: "wait-" + r.id.uuidString, header: r.trigger.label, symbol: r.trigger.kind.symbol,
                         detail: detail.isEmpty ? nil : detail, nodes: nodes)
    }

    private func nodeMeta(_ s: Step) -> String? {
        var parts: [String] = [store.type(s.typeID).name]
        if let l = s.limitText { parts.append(l) }
        return parts.joined(separator: " · ")
    }

    // MARK: Done

    @ViewBuilder
    private var done: some View {
        let list = store.completions(on: Day.today)
        if list.isEmpty {
            Text("Nothing finished yet today. The first one is the hardest.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
        }
        ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
            FlowRow(isFirst: i == 0, isLast: i == list.count - 1, lineColor: Theme.checkbox.opacity(0.5)) {
                ZStack {
                    Circle().fill(Theme.checkbox).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
            } content: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title)
                            .font(.system(size: 16))
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Text(doneMeta(c))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Day.clock(c.at))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func doneMeta(_ c: Completion) -> String {
        var parts = [store.type(c.typeID).name]
        if c.isRoutine && c.finishedWhole { parts.append("Routine finished") }
        if c.earnedToken { parts.append("+1 token") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Flow pieces

struct FlowNode: Identifiable {
    let id: String
    let title: String
    let meta: String?
    let color: Color
    let isCurrent: Bool
    let done: Bool
}

struct FlowBlock: Identifiable {
    let id: String
    let header: String
    let symbol: String
    let detail: String?
    let nodes: [FlowNode]
}

/// One routine or task: a header box, then its steps joined by a line.
struct FlowBlockView: View {
    let block: FlowBlock
    let accent: Color
    let isFirstBlock: Bool
    let isLastBlock: Bool
    var dimmed = false
    var start: (() -> Void)? = nil

    var body: some View {
        let line = Theme.checkbox.opacity(0.45)
        VStack(alignment: .leading, spacing: 0) {
            FlowRow(isFirst: isFirstBlock, isLast: isLastBlock && block.nodes.isEmpty, lineColor: line) {
                Image(systemName: block.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(dimmed ? Color.secondary : accent)
                    .frame(width: 26, height: 26)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } content: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(block.header).font(.system(size: 14, weight: .semibold))
                        if let d = block.detail {
                            Text(d).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let start {
                        Button("Start", action: start)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Start " + block.header)
                    }
                }
            }
            ForEach(Array(block.nodes.enumerated()), id: \.element.id) { j, node in
                FlowRow(isFirst: false, isLast: isLastBlock && j == block.nodes.count - 1, lineColor: line) {
                    Circle()
                        .strokeBorder(node.isCurrent ? accent : node.color, lineWidth: node.isCurrent ? 3 : 2)
                        .background(Circle().fill(node.isCurrent ? accent.opacity(0.25) : Theme.card))
                        .frame(width: node.isCurrent ? 18 : 14, height: node.isCurrent ? 18 : 14)
                } content: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(node.title)
                                .font(.system(size: 16, weight: node.isCurrent ? .semibold : .regular))
                                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                            if node.isCurrent {
                                Text("Now")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(accent.opacity(0.15), in: Capsule())
                            }
                        }
                        if let meta = node.meta {
                            Text(meta).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
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
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
