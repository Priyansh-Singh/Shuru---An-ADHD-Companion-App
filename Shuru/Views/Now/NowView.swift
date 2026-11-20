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
    @State private var panel: DayFlowPanel.Kind?

    private let fillDelay = 0.12
    private var dark: Bool { scheme == .dark }
    private var settings: AppSettings { store.settings }
    private var holdSeconds: Double { Double(settings.holdSeconds) }
    private var holdMode: Bool { settings.holdSeconds > 0 }

    var body: some View {
        let current = heldItem ?? store.queue().first
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.44)
            ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion && !isAnimating)) { context in
                let now = context.date
                let fill = fillValue(at: now)
                ZStack {
                    Theme.background.ignoresSafeArea()

                    OrbView(colors: Theme.orb(settings.palette, dark: dark), dark: dark, blur: settings.orbEdges.blur,
                            time: reduceMotion ? 0 : now.timeIntervalSinceReferenceDate * settings.orbSpeed.factor)
                        .scaleEffect(orbScale(now: now, fill: fill, empty: current == nil))
                        .animation(.easeInOut(duration: 3.2), value: store.breathPhase)
                        .position(center)

                    Rectangle()
                        .fill(EllipticalGradient(colors: [scrimColor, scrimColor.opacity(0)], center: .center,
                                                 startRadiusFraction: 0, endRadiusFraction: 0.5))
                        .frame(width: 380, height: 260)
                        .allowsHitTesting(false)
                        .position(center)
                        .accessibilityHidden(true)

                    HoldDisc(fill: fill, celebrationTime: celebrationTime(now), holding: pressStart != nil,
                             accent: Theme.accent(settings.palette), dark: dark)
                        .position(center)

                    if let c = celebration, settings.celebration != .off {
                        CelebrationView(t: now.timeIntervalSince(c.start), label: c.label, style: settings.celebration,
                                        palette: settings.palette, dark: dark)
                            .position(center)
                    }

                    if store.pauseStage == nil {
                        taskLayer(current: current, now: now, fill: fill)
                            .position(center)
                    }

                    hint
                        .position(x: center.x, y: geo.size.height - 92)

                    if store.pauseStage != nil {
                        PauseOverlay(item: store.queue().first)
                    }
                }
            }

            if store.pauseStage == nil && panel == nil && celebration == nil {
                flowHandles(height: geo.size.height)
            }

            if let panel {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { setPanel(nil) }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                DayFlowPanel(kind: panel) { setPanel(nil) }
                    .frame(maxHeight: geo.size.height * 0.8)
                    .frame(maxHeight: .infinity, alignment: panel == .upcoming ? .top : .bottom)
                    .padding(.top, panel == .upcoming ? 4 : 0)
                    .padding(.bottom, panel == .done ? 8 : 0)
                    .transition(.move(edge: panel == .upcoming ? .top : .bottom))
                    .zIndex(2)
            }
            }
            .simultaneousGesture(flowSwipe)
        }
        .sheet(item: $optionsItem) { item in
            OptionsSheet(item: item, holdMode: holdMode) { action in
                handle(action, item: item)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            if panel != nil {
                panel = nil
                store.nowPanelOpen = false
            }
        }
        .onAppear {
            hintVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { hintVisible = false }
        }
    }

    // MARK: Day flow (pull down: coming up, pull up: done)

    private func setPanel(_ p: DayFlowPanel.Kind?) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { panel = p }
        store.nowPanelOpen = p != nil
    }

    private var flowSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                guard store.pauseStage == nil, pressStart == nil, celebration == nil else { return }
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dy) > abs(dx) * 1.4 else { return }
                if panel == nil {
                    if dy > 70 { setPanel(.upcoming) } else if dy < -70 { setPanel(.done) }
                } else if (panel == .upcoming && dy < -60) || (panel == .done && dy > 60) {
                    setPanel(nil)
                }
            }
    }

    @ViewBuilder
    private func flowHandles(height: CGFloat) -> some View {
        let queue = store.queue()
        let comingCount = max(0, queue.count - 1) + store.cueRoutinesNotStarted().count
        let doneCount = store.completions(on: Day.today).count
        VStack {
            Button {
                setPanel(.upcoming)
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
                setPanel(.done)
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
        if holdMode {
            guard celebration == nil else { return }
            optionsItem = item
        } else {
            finish(item, fromHold: false)
        }
    }

    private func beginHold(_ item: NowItem) {
        guard celebration == nil, !finishing, store.pauseStage == nil else { return }
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
