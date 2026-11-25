import Foundation

extension SiteEntry {
    /// An IP address or CIDR range rather than a domain (tpws `--ipset`).
    var isAddress: Bool { IPRanges.isAddress(domain) }
}

/// The Sites page's actions beyond adding: delete with undo, move between the
/// lists, the automatic list, and the files the tunnel reads.
extension AppModel {
    /// The list files tpws reads, written before each start.
    struct ListFiles {
        var hasHostlist: Bool
        var hasExcludes: Bool
        var lists: TunnelLists
    }

    /// Writes My list's and Never Touch's domains and addresses to their
    /// files and names every turned-on subscription's file. Big lists are
    /// never joined: each file goes to tpws as its own flag.
    func writeListFiles() throws -> ListFiles {
        func split(_ entries: [SiteEntry]) -> (domains: [String], addresses: [String]) {
            let on = entries.filter(\.isEnabled)
            return (on.filter { !$0.isAddress }.map(\.domain), on.filter(\.isAddress).map(\.domain))
        }
        let include = split(includeSites)
        let exclude = split(excludeSites)
        try Domains.fileContents(include.domains).write(to: AppGroup.hostlistURL, atomically: true, encoding: .utf8)
        try Domains.fileContents(exclude.domains).write(to: AppGroup.excludeURL, atomically: true, encoding: .utf8)
        try Domains.fileContents(include.addresses).write(to: AppGroup.ipsetURL, atomically: true, encoding: .utf8)
        try Domains.fileContents(exclude.addresses).write(to: AppGroup.ipsetExcludeURL, atomically: true, encoding: .utf8)

        var out = TunnelLists()
        if !include.addresses.isEmpty { out.ipsets.append("ipset.txt") }
        if !exclude.addresses.isEmpty { out.ipsetExcludes.append("ipset-exclude.txt") }
        let fm = FileManager.default
        for s in lists.subscriptions where s.isEnabled && s.count > 0 && fm.fileExists(atPath: s.fileURL.path) {
            switch (s.kind, s.isExcluded) {
            case (.domains, false): out.hostlists.append(s.fileName)
            case (.domains, true): out.hostlistExcludes.append(s.fileName)
            case (.addresses, false): out.ipsets.append(s.fileName)
            case (.addresses, true): out.ipsetExcludes.append(s.fileName)
            }
        }
        // tpws creates the file itself, but only when the folder lets it.
        out.autoHostlist = lists.autoHostlist && scope == .listOnly
        if out.autoHostlist, !fm.fileExists(atPath: AppGroup.autoHostlistURL.path) {
            try Data().write(to: AppGroup.autoHostlistURL)
        }
        return ListFiles(hasHostlist: !include.domains.isEmpty, hasExcludes: !exclude.domains.isEmpty, lists: out)
    }

    // MARK: - My list and Never Touch

    /// Deletes sites and addresses; the Undo bar puts them back where they were.
    func deleteSites(_ ids: Set<String>) {
        let removed = sites.enumerated().filter { ids.contains($0.element.id) }
        guard !removed.isEmpty else { return }
        removeSites(ids)
        lists.undo = UndoItem(title: removed.count == 1
                              ? String(localized: "Deleted \(removed[0].element.domain)")
                              : String(localized: "Deleted \(removed.count) sites")) { [weak self] in
            guard let self else { return }
            for (index, entry) in removed where !sites.contains(where: { $0.id == entry.id }) {
                sites.insert(entry, at: min(index, sites.count))
            }
            restartIfRunning()
        }
    }

    /// Moves entries between Sites to Unblock and Never Touch.
    func moveSites(_ ids: Set<String>, excluded: Bool) {
        for i in sites.indices where ids.contains(sites[i].id) {
            let moved = SiteEntry(domain: sites[i].domain, isEnabled: sites[i].isEnabled, isExcluded: excluded)
            if sites.contains(where: { $0.id == moved.id }) { continue }
            sites[i] = moved
        }
        // Entries already in the other list stay only there.
        sites.removeAll { ids.contains($0.id) && $0.isExcluded != excluded }
        restartIfRunning()
    }

    /// Adds every domain and address in the text files. Returns how many were new.
    func importSites(from urls: [URL], excluded: Bool) -> Int {
        var added = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                added += addSites(text, excluded: excluded)
            }
        }
        return added
    }

    // MARK: - Subscriptions

    func setSubscriptionEnabled(_ subscription: ListSubscription, _ on: Bool) {
        lists.setEnabled(subscription.uuid, on)
    }

    // MARK: - The automatic list

    func setAutoHostlist(_ on: Bool) {
        guard lists.autoHostlist != on else { return }
        lists.autoHostlist = on
        restartIfRunning()
    }

    /// Moves sites from the automatic list to My list (excluded false) or Never Touch.
    func moveAutoSites(_ sites: [String], excluded: Bool) {
        guard !sites.isEmpty else { return }
        lists.removeAutoSites(Set(sites), undoTitle: nil)
        // New rows restart tpws; sites already in the list only left the
        // automatic file, which tpws must read again.
        if addSites(sites.joined(separator: "\n"), excluded: excluded) == 0 { restartIfRunning() }
    }

    func deleteAutoSites(_ sites: [String]) {
        lists.removeAutoSites(Set(sites), undoTitle: sites.count == 1
                              ? String(localized: "Deleted \(sites[0])")
                              : String(localized: "Deleted \(sites.count) sites"))
        restartIfRunning()
    }

    func clearAutoSites() {
        lists.removeAutoSites(Set(lists.autoSites), undoTitle: String(localized: "Cleared the automatic list"))
        restartIfRunning()
    }
}
