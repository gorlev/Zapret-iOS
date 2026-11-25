import Foundation
import Observation
import UIKit

/// A site list someone else keeps, downloaded from an address and used
/// together with My list or Never Touch. Its cleaned entries live in
/// `fileURL`; the row keeps what the list shows.
struct ListSubscription: Codable, Identifiable, Hashable {
    var uuid = UUID()
    var url: String
    /// Empty: the name comes from the address.
    var name = ""
    /// false: feeds Sites to Unblock. true: feeds Never Touch.
    var isExcluded = false
    var isEnabled = true
    var kind: ListKind = .domains
    /// Entries in the last good download: domains, or addresses and ranges.
    var count = 0
    var lastUpdated: Date?
    /// Why the last download failed, or nil after a good one.
    var lastError: String?
    var createdAt = Date.now

    var id: String { "s:" + uuid.uuidString }

    var displayName: String {
        if !name.isEmpty { return name }
        return URL(string: url).map(SiteListSubscription.defaultName) ?? url
    }

    /// The file's path relative to the App Group container, as tpws gets it.
    var fileName: String { "lists/\(uuid.uuidString).txt" }
    var fileURL: URL { AppGroup.url(relative: fileName) }
}

/// Something the person just removed, with the way to put it back. The Sites
/// page shows it as a bar with an Undo button for a few seconds.
struct UndoItem: Identifiable {
    let id = UUID()
    let title: String
    let restore: () -> Void
}

/// Subscriptions, the automatic list, and undo for the Sites page. My list
/// and Never Touch themselves stay in `AppModel.sites`.
@Observable
final class SiteLists {
    var subscriptions: [ListSubscription] { didSet { save() } }
    /// tpws `--hostlist-auto`: adds sites whose connections keep failing.
    var autoHostlist: Bool { didSet { save() } }
    /// The sites tpws added to the automatic list, in the order it added them.
    private(set) var autoSites: [String] = []
    private(set) var updating: Set<UUID> = []
    /// The last removal, until it is undone or the bar goes away.
    var undo: UndoItem?

    /// Called when the files tpws reads changed, so a running tunnel restarts.
    var onChange: () -> Void = {}

    /// About what fits in the tunnel extension's ~50 MB next to tpws and the
    /// tunnel: tpws keeps every entry of every list in memory.
    static let comfortableEntries = 250_000

    private var activeObserver: NSObjectProtocol?

    init() {
        let d = AppGroup.defaults
        if let data = d.data(forKey: "subscriptions"),
           let saved = try? JSONDecoder().decode([ListSubscription].self, from: data) {
            subscriptions = saved
        } else {
            subscriptions = []
        }
        autoHostlist = d.bool(forKey: "autoHostlist")
        reloadAutoSites()
        removeOrphanFiles()
        // Daily refresh: each time the app opens or comes back to the front.
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDue() }
        }
    }

    private func save() {
        let d = AppGroup.defaults
        d.set(try? JSONEncoder().encode(subscriptions), forKey: "subscriptions")
        d.set(autoHostlist, forKey: "autoHostlist")
    }

    func subscriptions(excluded: Bool) -> [ListSubscription] {
        subscriptions.filter { $0.isExcluded == excluded }
    }

    /// Entries tpws would load from the turned-on lists.
    var enabledEntryCount: Int {
        subscriptions.filter(\.isEnabled).reduce(0) { $0 + $1.count }
    }

    // MARK: - Subscriptions

    /// Downloads a list and adds it when the download works. Returns why it
    /// did not, for the sheet to show; a list that never downloaded is not added.
    func add(url: URL, name: String, excluded: Bool, kind: ListKind) async -> String? {
        if subscriptions(excluded: excluded).contains(where: { $0.url == url.absoluteString }) {
            return String(localized: "This list is already in your subscriptions.")
        }
        do {
            let entries = try await Self.download(url, kind: kind)
            var subscription = ListSubscription(url: url.absoluteString,
                                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                isExcluded: excluded, kind: kind)
            try Self.write(entries, to: subscription.fileURL)
            subscription.count = entries.count
            subscription.lastUpdated = .now
            subscriptions.append(subscription)
            onChange()
            return nil
        } catch {
            return Self.message(for: error)
        }
    }

    /// Downloads a list again. A failed download keeps the last good file
    /// and puts the error on the row.
    func update(_ id: UUID) async {
        guard !updating.contains(id), let current = subscriptions.first(where: { $0.uuid == id }),
              let url = URL(string: current.url) else { return }
        updating.insert(id)
        defer { updating.remove(id) }
        let result: Result<[String], Error>
        do { result = .success(try await Self.download(url, kind: current.kind)) } catch { result = .failure(error) }
        // Deleted while it downloaded: nothing to update.
        guard let i = subscriptions.firstIndex(where: { $0.uuid == id }) else { return }
        switch result {
        case .success(let entries):
            do {
                try Self.write(entries, to: subscriptions[i].fileURL)
                subscriptions[i].count = entries.count
                subscriptions[i].lastUpdated = .now
                subscriptions[i].lastError = nil
                if subscriptions[i].isEnabled { onChange() }
            } catch {
                subscriptions[i].lastError = error.localizedDescription
            }
        case .failure(let error):
            subscriptions[i].lastError = Self.message(for: error)
        }
    }

    func updateAll() {
        for subscription in subscriptions { Task { await update(subscription.uuid) } }
    }

    /// The turned-on lists whose last download is a day old.
    func updateDue() {
        for subscription in subscriptions where subscription.isEnabled
            && SiteListSubscription.isDue(lastUpdated: subscription.lastUpdated) {
            Task { await update(subscription.uuid) }
        }
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = subscriptions.firstIndex(where: { $0.uuid == id }), subscriptions[i].isEnabled != on else { return }
        subscriptions[i].isEnabled = on
        onChange()
    }

    /// Deletes lists; Undo brings them back with their downloaded files,
    /// which stay on disk until the next launch.
    func remove(_ ids: Set<UUID>) {
        let removed = subscriptions.enumerated().filter { ids.contains($0.element.uuid) }
        guard !removed.isEmpty else { return }
        subscriptions.removeAll { ids.contains($0.uuid) }
        onChange()
        undo = UndoItem(title: removed.count == 1
                        ? String(localized: "Deleted \(removed[0].element.displayName)")
                        : String(localized: "Deleted \(removed.count) subscriptions")) { [weak self] in
            guard let self else { return }
            for (index, subscription) in removed {
                subscriptions.insert(subscription, at: min(index, subscriptions.count))
            }
            onChange()
        }
    }

    /// Files of lists deleted in an earlier run (Undo cannot bring them back now).
    private func removeOrphanFiles() {
        let dir = AppGroup.listsFolder
        let known = Set(subscriptions.map { "\($0.uuid.uuidString).txt" })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in files where !known.contains(file) {
            try? FileManager.default.removeItem(at: dir.appending(path: file))
        }
    }

    // MARK: - The automatic list

    private func autoFileText() -> String {
        (try? String(contentsOf: AppGroup.autoHostlistURL, encoding: .utf8)) ?? ""
    }

    /// Reads the file again; the Sites page calls this while it is open.
    func reloadAutoSites() {
        let sites = AutoHostlistFile.sites(in: autoFileText())
        if sites != autoSites { autoSites = sites }
    }

    /// Takes sites out of the automatic file; Undo puts the old text back.
    func removeAutoSites(_ sites: Set<String>, undoTitle: String?) {
        guard !sites.isEmpty else { return }
        let old = autoFileText()
        writeAutoFile(AutoHostlistFile.contents(of: old, removing: sites))
        if let undoTitle {
            undo = UndoItem(title: undoTitle) { [weak self] in
                self?.writeAutoFile(old)
                self?.onChange()
            }
        }
    }

    private func writeAutoFile(_ text: String) {
        try? text.write(to: AppGroup.autoHostlistURL, atomically: true, encoding: .utf8)
        reloadAutoSites()
    }

    // MARK: - Download

    private enum DownloadError: Error { case status(Int) }

    private static func write(_ entries: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: AppGroup.listsFolder, withIntermediateDirectories: true)
        try Domains.fileContents(entries).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reads a list from the web and cleans it, off the main thread.
    private static func download(_ url: URL, kind: ListKind) async throws -> [String] {
        let data: Data
        if url.isFileURL {
            data = try await Task.detached { try Data(contentsOf: url) }.value
        } else {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            let (body, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DownloadError.status(http.statusCode)
            }
            data = body
        }
        return try await Task.detached { try SiteListSubscription.entries(from: data, kind: kind) }.value
    }

    private static func message(for error: Error) -> String {
        switch error {
        case DownloadError.status(let code): String(localized: "The server answered with error \(code).")
        case SiteListSubscription.Failure.notText: String(localized: "This address is not a site list.")
        case SiteListSubscription.Failure.empty: String(localized: "The list has no sites in it.")
        case SiteListSubscription.Failure.tooLarge: String(localized: "The list is too large.")
        case SiteListSubscription.Failure.onlyAddresses:
            String(localized: "This list has IP addresses, not sites. Choose IP Addresses as its kind.")
        case SiteListSubscription.Failure.onlyDomains:
            String(localized: "This list has sites, not IP addresses. Choose Sites as its kind.")
        case is Gzip.Failure: String(localized: "The gzip file is damaged.")
        default: error.localizedDescription
        }
    }
}
