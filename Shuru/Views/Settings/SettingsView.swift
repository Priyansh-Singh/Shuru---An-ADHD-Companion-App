import SwiftUI
import UniformTypeIdentifiers

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
                    labeled("Pause before distracting apps", "Instagram, YouTube, games… whichever you pick below")
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
                    if store.settings.tokens {
                        Picker("1 token buys", selection: $store.data.settings.minutesPerToken) {
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                        }
                        .padding(.leading, 16)
                    } else {
                        Picker("Free pass length", selection: $store.data.settings.snoozeMinutes) {
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                        }
                        .padding(.leading, 16)
                    }
                    Picker("Free 2-min quick looks a day", selection: $store.data.settings.quickLooksPerDay) {
                        Text("None").tag(0)
                        Text("1").tag(1)
                        Text("3").tag(3)
                        Text("5").tag(5)
                    }
                    .padding(.leading, 16)
                }
                Toggle(isOn: $store.data.settings.taskPause.animation()) {
                    labeled("Pause before every task", "Breathe, look back and look ahead each time a new task comes up")
                }
                if store.settings.taskPause {
                    Toggle("Breathe in and out", isOn: $store.data.settings.taskPauseBreath).padding(.leading, 16)
                    Toggle(isOn: $store.data.settings.taskPausePast) {
                        labeled("Look back", "The last time you put off something like it")
                    }
                    .padding(.leading, 16)
                    Toggle(isOn: $store.data.settings.taskPauseFuture) {
                        labeled("Look ahead", "Picture it done")
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
                Toggle(isOn: $store.data.settings.useLocation) {
                    labeled("Start place routines when I arrive", "Only for routines where you turned on “Start when I arrive”")
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Reminders are local, so they work even when the app is sideloaded. Location never leaves your phone.")
            }

            DistractingAppsSection()

            BackupSection()

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

// MARK: - Distracting apps

private struct SeenEntry: Identifiable {
    let key: String
    let app: SeenApp
    var id: String { key }
}

struct DistractingAppsSection: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            let seen: [SeenEntry] = store.data.seenApps
                .map { SeenEntry(key: $0.key, app: $0.value) }
                .sorted { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
            if seen.isEmpty {
                Text("No apps connected yet. Set up the automation below, then open one of the apps once.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            ForEach(seen) { entry in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent(store.settings.palette))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.app.name)
                        Text(status(entry.key)).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.unlockedUntil(entry.key) != nil {
                        Button("Lock now") { store.lockNow(entry.key) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .contextMenu {
                    Button("Forget this app", systemImage: "trash", role: .destructive) { store.forgetApp(entry.key) }
                }
            }
        } header: {
            Text("Connected apps")
        } footer: {
            Text("An app shows up here the first time its automation runs. Long-press to forget one.")
        }

        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("One automation covers every app").font(.system(size: 15, weight: .semibold))
                Text(Self.steps)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            Button {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            } label: {
                Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
            }
            Button("Try the pause now") { store.requestPause(appInput: "YouTube") }
        } header: {
            Text("Set up the automation")
        } footer: {
            Text("iOS doesn’t let any app create automations by itself, so this one-time setup is done by you. The check runs without opening Shuru, so going back to an app you unlocked doesn’t loop.")
        }
    }

    static let steps = """
    1. In Shortcuts, go to Automation and tap +.
    2. Choose App. Tap Choose and pick every app that drains you: Instagram, YouTube, X, Safari, Twitch, games…
    3. Keep “Is Opened” ticked, choose “Run Immediately”, then tap Next and New Blank Automation.
    4. Add Shuru’s “Check before opening” action. Tap App and pick Shortcut Input.
    5. Add an “If” action: If Result is true.
    6. Inside the If, add Shuru’s “Pause before opening” action, with App set to Shortcut Input.
    """

    private func status(_ key: String) -> String {
        if let until = store.unlockedUntil(key) {
            let mins = max(1, Int(until.timeIntervalSinceNow / 60))
            return "Unlocked · \(mins) min left"
        }
        return store.settings.pause ? "Pauses when opened" : "Pause is off"
    }
}

// MARK: - Backup

struct BackupSection: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var backup = Backup.shared
    @State private var pickingFolder = false
    @State private var pickingFile = false
    @State private var pendingRestore: Data?
    @State private var message: String?
    @State private var exporting = false
    @State private var exportDoc: BackupDocument?

    var body: some View {
        Section {
            if let name = backup.folderName {
                LabeledContent("Backing up to", value: name)
                Button("Back up now") {
                    message = backup.backUpNow(store) ? "Backed up just now." : (backup.lastError ?? "Couldn’t back up.")
                }
                Button("Change folder") { pickingFolder = true }
                    .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                        if case .success(let url) = result {
                            backup.useFolder(url)
                            message = backup.backUpNow(store) ? "Backed up to “\(url.lastPathComponent)”." : backup.lastError
                        }
                    }
                Button("Stop backing up", role: .destructive) {
                    backup.stop()
                    message = nil
                }
            } else {
                Button {
                    pickingFolder = true
                } label: {
                    Label("Choose a backup folder…", systemImage: "folder.badge.plus")
                }
                .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        backup.useFolder(url)
                        message = backup.backUpNow(store) ? "Backed up to “\(url.lastPathComponent)”." : backup.lastError
                    }
                }
            }
            Button {
                if let d = store.exportData() {
                    exportDoc = BackupDocument(data: d)
                    exporting = true
                }
            } label: {
                Label("Save a copy to Files…", systemImage: "square.and.arrow.down")
            }
            .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .json,
                          defaultFilename: "Shuru Backup " + Day.today) { result in
                switch result {
                case .success(let url): message = "Saved “\(url.lastPathComponent)”."
                case .failure: message = "Couldn’t save the copy."
                }
            }
            Button {
                pickingFile = true
            } label: {
                Label("Restore from a backup…", systemImage: "clock.arrow.circlepath")
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    if let raw = backup.read(url) {
                        pendingRestore = raw
                    } else {
                        message = "Couldn’t open that file."
                    }
                }
            }
            if let message {
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if let err = backup.lastError, message == nil {
                Text(err).font(.system(size: 13)).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text(footer)
        }
        .confirmationDialog("Replace everything in Shuru with this backup?",
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                if let raw = pendingRestore {
                    message = store.importData(raw) ? "Restored." : "That file isn’t a Shuru backup."
                }
                pendingRestore = nil
            }
        } message: {
            Text("Your tasks, routines, history, hours, tokens and settings will be swapped for the ones in the backup.")
        }
    }

    private var footer: String {
        var text = "Automatic backups go to a folder in iCloud Drive or On My iPhone: iOS only lets apps keep a folder from those. Shuru saves when you leave the app and keeps a daily copy for a week. For Google Drive, Dropbox or OneDrive, use Save a copy. On a new phone, install Shuru and restore from the file."
        if let last = backup.lastBackup {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            text = "Last backup: " + f.string(from: last) + ".\n" + text
        }
        return text
    }
}

/// The backup JSON as a file for "Save a copy to Files…".
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
