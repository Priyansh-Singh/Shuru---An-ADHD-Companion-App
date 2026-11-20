import Foundation
import UIKit

/// Backups to a folder you pick in Files: iCloud Drive, Google Drive, Dropbox, OneDrive,
/// or anything else that shows up there. No accounts or special permissions, so it works sideloaded.
final class Backup: ObservableObject {
    static let shared = Backup()

    @Published private(set) var folderName: String?
    @Published private(set) var lastBackup: Date?
    @Published private(set) var lastError: String?

    private let bookmarkKey = "shuru.backup.folder"
    private let lastKey = "shuru.backup.last"
    static let fileName = "Shuru Backup.json"

    init() {
        lastBackup = UserDefaults.standard.object(forKey: lastKey) as? Date
        if let url = resolveFolder() { folderName = url.lastPathComponent }
    }

    var isOn: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    // MARK: Folder

    func useFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            folderName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = "Couldn’t use that folder. Try another one."
        }
    }

    func stop() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
        lastError = nil
    }

    private func resolveFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: Backing up

    /// Writes "Shuru Backup.json", plus one copy per day for the last week.
    @discardableResult
    func backUpNow(_ store: AppStore) -> Bool {
        guard let json = store.exportData() else { return false }
        return write(json)
    }

    @discardableResult
    private func write(_ json: Data) -> Bool {
        guard let folder = resolveFolder() else { return false }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }

        var failure: Error?
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        let daily = folder.appendingPathComponent("Shuru Backup " + Day.today + ".json")
        coordinator.coordinate(writingItemAt: folder, options: [], error: &coordError) { dir in
            do {
                try json.write(to: dir.appendingPathComponent(Backup.fileName), options: [.atomic])
                try json.write(to: dir.appendingPathComponent(daily.lastPathComponent), options: [.atomic])
                self.pruneDailyCopies(in: dir)
            } catch {
                failure = error
            }
        }
        if coordError != nil || failure != nil {
            DispatchQueue.main.async { self.lastError = "Couldn’t write to “\(self.folderName ?? "the folder")”. Pick the folder again." }
            return false
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: lastKey)
        DispatchQueue.main.async {
            self.lastBackup = now
            self.lastError = nil
        }
        return true
    }

    private func pruneDailyCopies(in dir: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let daily = names.filter { $0.hasPrefix("Shuru Backup 2") && $0.hasSuffix(".json") }.sorted()
        for name in daily.dropLast(7) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// When you leave the app.
    func backUpInBackground(_ store: AppStore) {
        guard isOn else { return }
        var task: UIBackgroundTaskIdentifier = .invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Shuru backup") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        guard let json = store.exportData() else { return }
        DispatchQueue.global(qos: .utility).async {
            self.write(json)
            DispatchQueue.main.async {
                if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
            }
        }
    }

    /// On opening, if the last backup is more than a few hours old.
    func backUpIfStale(_ store: AppStore) {
        guard isOn else { return }
        if let last = lastBackup, Date().timeIntervalSince(last) < 4 * 3600 { return }
        guard let json = store.exportData() else { return }
        DispatchQueue.global(qos: .utility).async { self.write(json) }
    }

    // MARK: Restoring

    /// Reads a backup file picked in Files.
    func read(_ url: URL) -> Data? {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        var result: Data?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = try? Data(contentsOf: u)
        }
        return result
    }
}
