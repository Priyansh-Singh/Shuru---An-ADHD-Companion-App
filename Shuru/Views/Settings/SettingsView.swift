import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                ScreenHeader(title: "Settings")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            }

            Section("Look") {
                Picker("Theme", selection: $store.data.settings.appearance) {
                    ForEach(Appearance.allCases) { a in Text(a.name).tag(a) }
                }
                Picker("Orb colors", selection: $store.data.settings.palette) {
                    ForEach(Palette.allCases) { p in Text(p.name).tag(p) }
                }
                Picker("Orb motion", selection: $store.data.settings.orbSpeed) {
                    ForEach(OrbSpeed.allCases) { p in Text(p.name).tag(p) }
                }
                Picker("Orb edges", selection: $store.data.settings.orbEdges) {
                    ForEach(OrbEdges.allCases) { p in Text(p.name).tag(p) }
                }
                Picker("When you finish something", selection: $store.data.settings.celebration) {
                    ForEach(CelebrationStyle.allCases) { p in Text(p.name).tag(p) }
                }
            }

            Section("Now screen") {
                Picker("To finish a task", selection: $store.data.settings.holdSeconds) {
                    Text("Tap").tag(0)
                    Text("Hold 2 s").tag(2)
                    Text("Hold 3 s").tag(3)
                    Text("Hold 5 s").tag(5)
                }
                Toggle("Show the “if” line", isOn: $store.data.settings.showTrigger)
                Toggle("Show page dots", isOn: $store.data.settings.showDots)
                Toggle("Vibration", isOn: $store.data.settings.haptics)
            }

            Section {
                Toggle(isOn: $store.data.settings.brainDump) {
                    labeled("Brain dump", "A quick place to empty your head")
                }
                Toggle(isOn: $store.data.settings.hours) {
                    labeled("Hours", "Log each hour and watch the day pass")
                }
                Toggle(isOn: $store.data.settings.pause.animation()) {
                    labeled("Pause before scrolling", "When your Instagram shortcut opens the app")
                }
                if store.settings.pause {
                    Toggle("Breathe", isOn: $store.data.settings.pauseBreath).padding(.leading, 16)
                    Toggle(isOn: $store.data.settings.pausePast) {
                        labeled("Look back", "Remember the last time you put off this kind of task")
                    }
                    .padding(.leading, 16)
                    Toggle(isOn: $store.data.settings.pauseFuture) {
                        labeled("Look ahead", "Picture it done later today")
                    }
                    .padding(.leading, 16)
                    Toggle("Say it out loud", isOn: $store.data.settings.pauseSay).padding(.leading, 16)
                    Picker("Back to scrolling for", selection: $store.data.settings.snoozeMinutes) {
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                    .padding(.leading, 16)
                }
                Toggle(isOn: $store.data.settings.tokens.animation()) {
                    labeled("Tokens and rewards", "1 for each task or routine you finish")
                }
                if store.settings.tokens {
                    Picker("Most tokens a day", selection: $store.data.settings.tokenCap) {
                        Text("5").tag(5)
                        Text("8").tag(8)
                        Text("12").tag(12)
                        Text("No limit").tag(0)
                    }
                    .padding(.leading, 16)
                    Toggle(isOn: $store.data.settings.tokenWeekly) {
                        labeled("Clear tokens every Monday", "Unspent tokens go back to zero, so each week starts fresh")
                    }
                    .padding(.leading, 16)
                }
            } header: {
                Text("Features")
            }

            if store.settings.hours {
                Section("Hours and check-ins") {
                    Stepper("Day starts at \(Day.hourLabel(store.settings.wakeHour))", value: $store.data.settings.wakeHour, in: 4...12)
                    Stepper("Day ends at \(Day.hourLabel(store.settings.bedHour))", value: $store.data.settings.bedHour, in: 19...24)
                    Picker("Ask me to log", selection: $store.data.settings.checkEvery) {
                        Text("Hourly").tag(1)
                        Text("Every 2 h").tag(2)
                        Text("Every 3 h").tag(3)
                        Text("Never").tag(0)
                    }
                    Picker("On the hour", selection: $store.data.settings.chime) {
                        ForEach(Chime.allCases) { c in Text(c.name).tag(c) }
                    }
                    Toggle(isOn: $store.data.settings.autoLog) {
                        labeled("Log tasks automatically", "Starting or finishing a task fills in Hours")
                    }
                }
            }

            Section {
                Toggle("Remind me of timed routines", isOn: $store.data.settings.remindRoutines)
            } header: {
                Text("Reminders")
            } footer: {
                Text("Reminders are local, so they work even when the app is sideloaded.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make Instagram open Shuru first").font(.system(size: 15, weight: .semibold))
                    Text("1. Open the Shortcuts app and go to Automation.\n2. Tap +, choose App, pick Instagram and “Is Opened”.\n3. Choose “Run Immediately”.\n4. Add the action “Pause before scrolling” from Shuru. In LiveContainer, use its “Launch App” action with the URL shuru://pause instead.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Button("Try the pause now") { store.requestPause() }
            } header: {
                Text("Instagram pause")
            }

            Section {
                Button("Reset everything", role: .destructive) { confirmReset = true }
            } header: {
                Text("Start over")
            } footer: {
                Text(versionLine)
            }

            Section {
                Color.clear.frame(height: 60)
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .confirmationDialog("Delete all tasks, routines, history and tokens?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) { store.resetEverything() }
        } message: {
            Text("Your settings stay. This can’t be undone.")
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Shuru \(version), build \(build)"
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}
