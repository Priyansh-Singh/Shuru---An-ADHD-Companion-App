import SwiftUI

/// "Stop the action": shown when your Instagram shortcut opens Shuru.
/// Breathe, look back, look ahead, say it out loud, then decide.
struct PauseOverlay: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    let item: NowItem?

    private var dark: Bool { scheme == .dark }
    private var stage: PauseStage { store.pauseStage ?? .decide }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(Day.clock(Date()))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                if let since = sinceLine {
                    Text(since).font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundStyle(Theme.orbSub(dark))
            .padding(.top, 24)

            Spacer()

            VStack(spacing: 14) {
                if let tag = tag, stage == .past || stage == .future {
                    HStack(spacing: 7) {
                        TypeDot(color: tag.color)
                        Text(tag.name).font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.4)
                    .accessibilityAddTraits(.isHeader)
                Text(bodyText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.orbSub(dark))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .shadow(color: dark ? .black.opacity(0.5) : .white.opacity(0.7), radius: 14)
            .padding(.horizontal, 32)

            Spacer()

            buttons
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: store.pauseStage) {
            guard store.pauseStage == .breath else { return }
            store.breathPhase = .inhale
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            if Task.isCancelled || store.pauseStage != .breath { return }
            store.breathPhase = .exhale
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            if Task.isCancelled || store.pauseStage != .breath { return }
            store.advancePause()
        }
    }

    // MARK: Content

    private var tag: TaskType? {
        guard let item else { return nil }
        return store.type(item.step.typeID)
    }

    private var taskTitle: String {
        guard let item else { return "" }
        return store.displayTitle(item)
    }

    private var sinceLine: String? {
        guard store.settings.hours else { return nil }
        guard let last = store.data.lastCheckIn else { return "No check-ins yet today" }
        let mins = Int(Date().timeIntervalSince(last) / 60)
        if mins < 1 { return "You just checked in." }
        if mins < 60 { return "\(mins) min since your last check-in" }
        let h = mins / 60, m = mins % 60
        return "\(h) h" + (m > 0 ? " \(m) min" : "") + " since your last check-in"
    }

    private var title: String {
        switch stage {
        case .breath: return "Pause."
        case .past: return "Look back."
        case .future: return "Look ahead."
        case .say: return "Say it out loud."
        case .decide: return "What now?"
        }
    }

    private var bodyText: String {
        let hasTask = item != nil
        switch stage {
        case .breath:
            return store.breathPhase == .exhale ? "…and let it go." : "Breathe in…"
        case .past:
            return hasTask
                ? "Remember the last time you put off something like\n“\(taskTitle)”.\nHow did it feel, hanging over you?"
                : "Remember the last time you meant to stop scrolling and didn’t.\nHow did the rest of that day go?"
        case .future:
            return hasTask
                ? "Now picture “\(taskTitle)”\ndone, later today.\nHow does that version of you feel?"
                : "Picture yourself an hour from now, rested instead of drained.\nWhich version do you want?"
        case .say:
            guard let item else { return "“I’ll take a real break.”" }
            var core = item.step.smallerOrDefault
            for prefix in ["Just start: ", "Just "] where core.hasPrefix(prefix) {
                core = String(core.dropFirst(prefix.count))
            }
            let first: String = core.prefix(1).lowercased()
            let rest: String = String(core.dropFirst())
            return "“First, I’ll " + first + rest + ".”"
        case .decide:
            return hasTask ? "Next up: “\(taskTitle)”" : "Nothing planned. A real break counts too."
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        switch stage {
        case .breath:
            Button("Skip") { store.advancePause() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
        case .past, .future:
            Button {
                store.advancePause()
            } label: {
                Text(stage == .past ? "I remember" : "I can see it")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        case .say, .decide:
            VStack(spacing: 8) {
                Button {
                    store.endPause()
                    if let item { store.startTimer(for: item) }
                } label: {
                    Text(stage == .say ? "Said it. Starting now" : "Start it now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent(dark))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.accent(store.settings.palette), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    store.backToInstagram()
                } label: {
                    Text("Back to Instagram for \(store.settings.snoozeMinutes) min")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
