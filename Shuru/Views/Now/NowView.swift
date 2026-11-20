import SwiftUI
import UIKit

struct CelebrationState: Equatable {
    let start: Date
    let label: String
    let fromHold: Bool
}

/// The main screen: one next thing, over the orb. Hold it to finish.
struct NowView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pressStart: Date?
    @State private var releaseAt: Date?
    @State private var releaseFrom: Double = 0
    @State private var celebration: CelebrationState?
    @State private var heldItem: NowItem?
    @State private var optionsItem: NowItem?
    @State private var nudge = false
    @State private var hintVisible = true
    @State private var buzz: Task<Void, Never>?
    @State private var finishing = false
    @State private var flow: FlowMode = .rest
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.45, dampingFraction: 0.86)))
    private var dragY: CGFloat = 0

    enum FlowMode { case rest, upcoming, done }

    private let fillDelay = 0.12
    private var dark: Bool { scheme == .dark }
    private var settings: AppSettings { store.settings }
    private var holdSeconds: Double { Double(settings.holdSeconds) }
    private var holdMode: Bool { settings.holdSeconds > 0 }

    var body: some View {
        let current = heldItem ?? store.queue().first
        GeometryReader { geo in
            let h = geo.size.height
            let taskY = taskCenterY(h)
            let taskPoint = CGPoint(x: geo.size.width / 2, y: taskY)
            let orbPoint = CGPoint(x: geo.size.width / 2, y: h * 0.44 + (taskY - h * 0.44) * 0.3)
            let upReveal = Ease.clamp(Double((taskY - h * 0.44) / (h * 0.36)))
            let doneReveal = Ease.clamp(Double((h * 0.44 - taskY) / (h * 0.26)))
            ZStack {
                TimelineView(.animation(minimumInterval: nil, paused: store.page != .now || (reduceMotion && !isAnimating))) { context in
                    let now = context.date
                    let fill = fillValue(at: now)
                    ZStack {
                        Theme.background.ignoresSafeArea()

                        OrbView(colors: Theme.orb(settings.palette, dark: dark), dark: dark, blur: settings.orbEdges.blur,
                                time: reduceMotion ? 0 : now.timeIntervalSinceReferenceDate * settings.orbSpeed.factor)
                            .scaleEffect(orbScale(now: now, fill: fill, empty: current == nil))
                            .animation(.easeInOut(duration: 3.2), value: store.breathPhase)
                            .position(orbPoint)

                        Rectangle()
                            .fill(EllipticalGradient(colors: [scrimColor, scrimColor.opacity(0)], center: .center,
                                                     startRadiusFraction: 0, endRadiusFraction: 0.5))
                            .frame(width: 380, height: 260)
                            .allowsHitTesting(false)
                            .position(taskPoint)
                            .accessibilityHidden(true)

                        HoldDisc(fill: fill, celebrationTime: celebrationTime(now), holding: pressStart != nil,
                                 accent: Theme.accent(settings.palette), dark: dark)
                            .position(taskPoint)

                        if let c = celebration, settings.celebration != .off {
                            CelebrationView(t: now.timeIntervalSince(c.start), label: c.label, style: settings.celebration,
                                            palette: settings.palette, dark: dark)
                                .position(taskPoint)
                        }

                        if store.pauseStage == nil {
                            taskLayer(current: current, now: now, fill: fill)
                                .scaleEffect(1 - 0.12 * CGFloat(max(upReveal, doneReveal)))
                                .position(taskPoint)
                        }

                        hint
                            .opacity(flow == .rest ? 1 : 0)
                            .position(x: taskPoint.x, y: h - 92)

                        if store.pauseStage != nil {
                            PauseOverlay(item: store.queue().first)
                        }
                    }
                }

                if store.pauseStage == nil {
                    flowColumns(height: h, width: geo.size.width, taskY: taskY, upReveal: upReveal, doneReveal: doneReveal)
                }

                if store.pauseStage == nil && flow == .rest && celebration == nil {
                    flowHandles(height: h)
                }

                if let banner = store.banner {
                    Text(banner)
                        .font(.system(size: 13, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.card2, in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.top, 56)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(3)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                if store.banner == banner { withAnimation { store.banner = nil } }
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(flowDrag)
        }
        .sheet(item: $optionsItem) { item in
            OptionsSheet(item: item, holdMode: holdMode) { action in
                handle(action, item: item)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            flow = .rest
        }
        .task(id: primeKey(current)) {
            // "Before you start": breathe, look back, look ahead, once per task per day.
            guard let item = current, settings.taskPause, store.page == .now, flow == .rest,
                  celebration == nil, heldItem == nil, store.pauseStage == nil,
                  !store.data.primed.contains(item.id) else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, store.page == .now, celebration == nil, store.pauseStage == nil else { return }
            store.startTaskPause(for: item)
        }
        .onAppear {
            hintVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { hintVisible = false }
        }
    }

    // MARK: Day flow (pull down: coming up above the task, pull up: done below it)

    private func baseY(_ mode: FlowMode, _ h: CGFloat) -> CGFloat {
        switch mode {
        case .rest: return h * 0.44
        case .upcoming: return h * 0.80
        case .done: return h * 0.18
        }
    }

    private func taskCenterY(_ h: CGFloat) -> CGFloat {
        let y = baseY(flow, h) + dragY
        return min(max(y, h * 0.16), h * 0.82)
    }

    private func setFlow(_ mode: FlowMode) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            flow = mode
        }
    }

    private var canFlow: Bool { store.pauseStage == nil && pressStart == nil && celebration == nil }

    private var flowDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($dragY) { v, state, _ in
                guard canFlow else { return }
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dy) > abs(dx) * 0.87 else { return }
                state = dy * 0.65
            }
            .onEnded { v in
                guard canFlow else { return }
                let dx = v.translation.width, dy = v.translation.height
                var next = flow
                if abs(dy) > abs(dx) * 0.87 {
                    switch flow {
                    case .rest:
                        if dy > 70 { next = .upcoming } else if dy < -70 { next = .done }
                    case .upcoming:
                        if dy < -50 { next = .rest }
                    case .done:
                        if dy > 50 { next = .rest }
                    }
                }
                if next != flow && settings.haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
                setFlow(next)
            }
    }

    @ViewBuilder
    private func flowColumns(height h: CGFloat, width: CGFloat, taskY: CGFloat, upReveal: Double, doneReveal: Double) -> some View {
        // Coming up: fills the space above the task, nearest step at the bottom.
        let upBottom = baseY(.upcoming, h) - 70
        let upTop: CGFloat = 52
        let upHeight = max(0, upBottom - upTop)
        DayFlowColumn(kind: .upcoming, maxRows: max(2, Int(upHeight / 54)))
            .padding(.horizontal, 24)
            .frame(width: width, height: upHeight, alignment: .bottom)
            .position(x: width / 2, y: upTop + upHeight / 2 + (taskY - baseY(.upcoming, h)))
            .opacity(upReveal)
            .allowsHitTesting(flow == .upcoming)
            .accessibilityHidden(flow != .upcoming)

        // Done: fills the space below the task, most recent at the top.
        let doneTop = baseY(.done, h) + 70
        let doneBottom = h - 110
        let doneHeight = max(0, doneBottom - doneTop)
        DayFlowColumn(kind: .done, maxRows: max(2, Int(doneHeight / 54)))
            .padding(.horizontal, 24)
            .frame(width: width, height: doneHeight, alignment: .top)
            .position(x: width / 2, y: doneTop + doneHeight / 2 + (taskY - baseY(.done, h)))
            .opacity(doneReveal)
            .allowsHitTesting(flow == .done)
            .accessibilityHidden(flow != .done)
    }

    @ViewBuilder
    private func flowHandles(height: CGFloat) -> some View {
        let queue = store.queue()
        let comingCount = max(0, queue.count - 1) + store.cueRoutinesNotStarted().count
        let doneCount = store.completions(on: Day.today).count
        VStack {
            Button {
                setFlow(.upcoming)
            } label: {
                HStack(spacing: 6) {
                    Text(comingCount == 0 ? "Coming up" : "\(comingCount) coming up")
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Coming up today: \(comingCount)")
            .accessibilityHint("Shows the rest of today’s routines and tasks")
            .padding(.top, 6)
            Spacer()
            Button {
                setFlow(.done)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                    Text(doneCount == 0 ? "Done today" : "\(doneCount) done today")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done today: \(doneCount)")
            .padding(.bottom, 128)
        }
        .frame(height: height)
    }

    private func primeKey(_ item: NowItem?) -> String {
        [item?.id ?? "none",
         celebration == nil ? "idle" : "party",
         store.page == .now ? "here" : "away",
         flow == .rest ? "rest" : "flow",
         settings.taskPause ? "on" : "off"].joined(separator: "|")
    }

    // MARK: Layers

    private var scrimColor: Color { dark ? Color.black.opacity(0.45) : Color(hex: "#F7F4EF", opacity: 0.4) }

    private var isAnimating: Bool { pressStart != nil || releaseAt != nil || celebration != nil || store.pauseStage != nil }

    @ViewBuilder
    private func taskLayer(current: NowItem?, now: Date, fill: Double) -> some View {
        let t = celebrationTime(now)
        let opacity = textOpacity(t: t)
        let lift = t.map { $0 < 0.3 ? -14 * Ease.outCubic($0 / 0.3) : 0 } ?? 0
        if let item = current {
            VStack(spacing: 14) {
                if settings.showTrigger {
                    Text(triggerLine(item))
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(Theme.orbSub(dark))
                }
                Text(store.displayTitle(item))
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                if let line = timerLine(item, now: now) {
                    Text(line)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.orbSub(dark))
                }
                if let limit = item.step.limitText {
                    Text(limit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.orbSub(dark))
                        .multilineTextAlignment(.center)
                }
            }
            .shadow(color: dark ? .black.opacity(0.5) : .white.opacity(0.7), radius: 14)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .frame(maxWidth: 330)
            .contentShape(Rectangle())
            .scaleEffect(1 - 0.05 * fill)
            .offset(y: lift)
            .opacity(opacity)
            .onTapGesture { tapped(item) }
            .onLongPressGesture(minimumDuration: holdMode ? holdSeconds + fillDelay : 0.48, maximumDistance: 16) {
                if holdMode { finishFromHold(item) } else { optionsItem = item }
            } onPressingChanged: { pressing in
                guard holdMode else { return }
                if pressing { beginHold(item) } else { endHold(item) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(store.displayTitle(item))
            .accessibilityHint(holdMode ? "Press and hold to mark done. Double tap for options." : "Double tap to mark done.")
            .accessibilityAction(named: "Mark done") { finish(item, fromHold: false) }
            .accessibilityAction(named: "Options") { optionsItem = item }
        } else {
            let waiting = store.waitingRoutines()
            VStack(spacing: 16) {
                Button {
                    store.go(to: .calendar)
                } label: {
                    VStack(spacing: 12) {
                        Text("That’s everything.")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(waiting.isEmpty ? "Nothing next. Go enjoy it." : "Nothing else until one of these happens.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.orbSub(dark))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the calendar")
                ForEach(waiting.prefix(3)) { r in
                    WaitingCueButton(routine: r, accent: Theme.accent(settings.palette)) {
                        store.cueHappened(routineID: r.id, announce: false)
                    }
                }
            }
            .opacity(opacity)
        }
    }

    private var hint: some View {
        let text: String
        if nudge {
            text = "Keep holding until it fills"
        } else {
            text = holdMode ? "Hold to finish · tap for options" : "Tap when done · hold for options"
        }
        return Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .opacity((nudge || hintVisible) && store.pauseStage == nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.6), value: nudge || hintVisible)
            .accessibilityHidden(true)
    }

    private func triggerLine(_ item: NowItem) -> String {
        item.isChain ? item.triggerLabel + " · \(item.stepIndex + 1) of \(item.stepCount)" : item.triggerLabel
    }

    private func timerLine(_ item: NowItem, now: Date) -> String? {
        guard let timer = store.timer, timer.itemID == item.id else { return nil }
        let left = timer.end.timeIntervalSince(now)
        if left <= 0 { return "Five minutes done. Keep going?" }
        let m = Int(left) / 60, s = Int(left) % 60
        return String(format: "%d:%02d left", m, s)
    }

    // MARK: Timing

    private func celebrationTime(_ now: Date) -> Double? {
        guard let c = celebration else { return nil }
        return now.timeIntervalSince(c.start)
    }

    private func textOpacity(t: Double?) -> Double {
        guard let t else { return 1 }
        if heldItem != nil { return t < 0.22 ? 1 - t / 0.22 : 0 }
        return min(1, max(0, (t - 1.75) / 0.36))
    }

    private func fillValue(at now: Date) -> Double {
        if let t = celebrationTime(now), celebration?.fromHold == true, t < 1.9 { return 1 }
        if let start = pressStart {
            let raw = (now.timeIntervalSince(start) - fillDelay) / max(0.5, holdSeconds)
            return reduceMotion ? Ease.clamp(raw) : Ease.hold(raw)
        }
        if let r = releaseAt {
            let p = now.timeIntervalSince(r) / 0.46
            if p >= 1 { return 0 }
            return max(0, releaseFrom * (1 - Ease.inBack(p)))
        }
        return 0
    }

    private func orbScale(now: Date, fill: Double, empty: Bool) -> CGFloat {
        var s = 1 + 0.1 * fill
        if let t = celebrationTime(now), t < 0.9 {
            s *= Ease.keyframes(t, [(0, 1), (0.3, 1.12), (0.9, 1)], ease: Ease.inOut)
        }
        switch store.breathPhase {
        case .inhale: s *= 1.16
        case .exhale: s *= 0.86
        case .none: if store.pauseStage == .breath { s *= 0.9 }
        }
        if empty && celebration == nil { s *= 0.88 }
        return CGFloat(s)
    }

    // MARK: Gestures

    private func tapped(_ item: NowItem) {
        if flow != .rest {
            setFlow(.rest)
            return
        }
        if holdMode {
            guard celebration == nil else { return }
            optionsItem = item
        } else {
            finish(item, fromHold: false)
        }
    }

    private func beginHold(_ item: NowItem) {
        guard celebration == nil, !finishing, store.pauseStage == nil, flow == .rest else { return }
        releaseAt = nil
        nudge = false
        hintVisible = false
        pressStart = Date()
        buzz?.cancel()
        guard settings.haptics else { return }
        let total = holdSeconds
        buzz = Task { @MainActor in
            let marks: [Double] = [0.2, 0.45, 0.7, 0.9]
            var waited = 0.0
            for (i, f) in marks.enumerated() {
                let at = fillDelay + total * f
                try? await Task.sleep(nanoseconds: UInt64(max(0, at - waited) * 1_000_000_000))
                if Task.isCancelled { return }
                waited = at
                let gen = UIImpactFeedbackGenerator(style: i < 2 ? .light : .medium)
                gen.impactOccurred(intensity: 0.5 + Double(i) * 0.15)
            }
        }
    }

    private func endHold(_ item: NowItem) {
        guard let start = pressStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= holdSeconds + fillDelay - 0.04 {
            finishFromHold(item)
            return
        }
        buzz?.cancel()
        releaseFrom = fillValue(at: Date())
        pressStart = nil
        releaseAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let r = releaseAt, Date().timeIntervalSince(r) >= 0.46 { releaseAt = nil }
        }
        if elapsed > 0.26 {
            nudge = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { nudge = false }
        }
    }

    private func finishFromHold(_ item: NowItem) {
        guard pressStart != nil, !finishing else { return }
        buzz?.cancel()
        pressStart = nil
        releaseAt = nil
        finish(item, fromHold: true)
    }

    private func finish(_ item: NowItem, fromHold: Bool) {
        guard !finishing, celebration == nil else { return }
        finishing = true
        hintVisible = false
        heldItem = item
        let result = store.complete(item)
        if settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        celebration = CelebrationState(start: Date(), label: result.label, fromHold: fromHold)
        UIAccessibility.post(notification: .announcement, argument: result.label.isEmpty ? "Done" : "Done. " + result.label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) { heldItem = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            celebration = nil
            finishing = false
        }
    }

    // MARK: Options

    private func handle(_ action: OptionsSheet.Action, item: NowItem) {
        optionsItem = nil
        switch action {
        case .smaller:
            store.toggleSmaller(item)
        case .timer:
            if store.timer?.itemID == item.id { store.stopTimer() } else { store.startTimer(for: item) }
        case .notNow:
            store.notNow(item)
        case .pickOne:
            store.pickOne(excluding: item)
        case .done:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { finish(item, fromHold: true) }
        }
    }
}

// MARK: - Hold disc

struct HoldDisc: View {
    let fill: Double
    let celebrationTime: Double?
    let holding: Bool
    let accent: Color
    let dark: Bool

    var body: some View {
        let t = celebrationTime
        let pop: Double = t.map { Ease.keyframes($0, [(0, 1), (0.245, 1.15), (0.7, 1)], ease: Ease.inOut) } ?? 1
        let fade: Double = t.map { $0 < 1.15 ? 1 : max(0, 1 - ($0 - 1.15) / 0.6) } ?? 1
        let ringOn = holding || (t.map { $0 < 1.15 } ?? false)
        ZStack {
            Circle()
                .strokeBorder(dark ? Color(hex: "#F5F2EC", opacity: 0.28) : Color(hex: "#17161A", opacity: 0.2), lineWidth: 1.5)
                .frame(width: 252, height: 252)
                .scaleEffect(ringOn ? 1 : 0.9)
                .opacity(ringOn ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.6), value: ringOn)
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(dark ? 0.28 : 0.14), accent.opacity(dark ? 0.4 : 0.22), accent.opacity(dark ? 0.62 : 0.36)],
                                     center: .center, startRadius: 0, endRadius: 126))
                .overlay(Circle().strokeBorder(accent.opacity(dark ? 0.9 : 0.75), lineWidth: 2))
                .shadow(color: accent.opacity(dark ? 0.35 : 0.18), radius: 20)
                .frame(width: 252, height: 252)
                .scaleEffect(CGFloat(max(0.001, fill * pop)))
                .opacity(fill > 0.002 ? fade : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A cue routine that hasn't started yet, shown on Now when nothing else is next.
struct WaitingCueButton: View {
    let routine: Routine
    let accent: Color
    let start: () -> Void

    var body: some View {
        Button(action: start) {
            HStack(spacing: 8) {
                Image(systemName: routine.trigger.kind.symbol)
                Text(routine.trigger.label).lineLimit(1)
                Text("Start").foregroundStyle(accent)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start: " + routine.trigger.label + ", " + routine.title)
    }
}
