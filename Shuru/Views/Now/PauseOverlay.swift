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
                if let app = store.pauseApp, app.key != GuardedAppInfo.anyApp.key {
                    Text("You opened " + app.name).font(.system(size: 13, weight: .semibold))
                }
                if store.pauseForTask {
                    Text("Before you start").font(.system(size: 13, weight: .semibold))
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
            if store.pauseForTask && store.isLastPauseStage(stage) {
                VStack(spacing: 8) {
                    Button {
                        store.endPause()
                    } label: {
                        Text("Start it now")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.onAccent(dark))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.accent(store.settings.palette), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    notNowButton
                }
            } else {
                VStack(spacing: 8) {
                    Button {
                        store.advancePause()
                    } label: {
                        Text(stage == .past ? "I remember" : "I can see it")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    if store.pauseForTask {
                        Button("Skip to the task") { store.endPause() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                }
            }
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
                unlockOptions
            }
        }
    }

    /// For the before-a-task pause: push this one later instead.
    private var notNowButton: some View {
        Button {
            store.endPause()
            if let item { store.notNow(item) }
        } label: {
            Text("Not now")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: Spending tokens on the app

    private var appName: String {
        guard let app = store.pauseApp, app.key != GuardedAppInfo.anyApp.key else { return "the app" }
        return app.name
    }

    @ViewBuilder
    private var unlockOptions: some View {
        let s = store.settings
        if s.tokens {
            let balance = store.data.tokens
            HStack(spacing: 8) {
                unlockButton(tokens: 1, minutes: s.minutesPerToken, enabled: balance >= 1)
                unlockButton(tokens: 2, minutes: s.minutesPerToken * 2, enabled: balance >= 2)
            }
            Text(balance == 0 ? "No tokens left. Finish something to earn one." : "You have \(balance) token" + (balance == 1 ? "." : "s."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.orbSub(dark))
        } else {
            Button {
                store.backFree()
            } label: {
                Text("Back to \(appName) for \(s.snoozeMinutes) min")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
        }
        if s.quickLooksPerDay > 0 {
            let left = store.quickLooksLeft
            Button {
                store.quickLook()
            } label: {
                Text(left > 0 ? "Quick look · 2 min (\(left) left today)" : "No quick looks left today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(left > 0 ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(left == 0)
        }
    }

    private func unlockButton(tokens: Int, minutes: Int, enabled: Bool) -> some View {
        Button {
            store.buyTime(tokens: tokens)
        } label: {
            VStack(spacing: 2) {
                Text("\(minutes) min of \(appName)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(tokens == 1 ? "1 token" : "\(tokens) tokens")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Spend \(tokens) token\(tokens == 1 ? "" : "s") for \(minutes) minutes of \(appName)")
    }
}
