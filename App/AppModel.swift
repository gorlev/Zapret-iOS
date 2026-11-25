import Foundation
import NetworkExtension
import Observation

/// One site in My list or Never Touch.
struct SiteEntry: Codable, Identifiable, Hashable {
    var domain: String
    var isEnabled = true
    var isExcluded = false
    var id: String { (isExcluded ? "x:" : "i:") + domain }
}

/// Everything the screens show and change: the switch, the strategy, the
/// sites, and the log. The bypass itself runs in the tunnel extension.
@Observable
final class AppModel {
    enum State: Equatable {
        case stopped, starting, running, stopping
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var startedAt: Date?
    private(set) var connections = 0
    private(set) var hostsSeen: [String] = []
    private(set) var logLines: [LogLine] = []
    private(set) var tunnelLog: [String] = []

    var presetID: String { didSet { save(); restartIfRunning() } }
    var scope: Scope { didSet { save(); restartIfRunning() } }
    var dns: DNSChoice { didSet { save(); restartIfRunning() } }
    var sites: [SiteEntry] { didSet { save() } }

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var logTimer: Timer?
    private var logOffset: UInt64 = 0
    private var nextLineID = 0
    private var restartPending = false

    var preset: Preset { Preset.with(id: presetID) ?? Preset.all[0] }
    var isOn: Bool { state == .running || state == .starting }
    var includeSites: [SiteEntry] { sites.filter { !$0.isExcluded } }
    var excludeSites: [SiteEntry] { sites.filter(\.isExcluded) }

    init() {
        let d = AppGroup.defaults
        presetID = d.string(forKey: "presetID") ?? Preset.defaultID
        scope = d.string(forKey: "scope").flatMap(Scope.init) ?? .allSites
        dns = d.string(forKey: "dns").flatMap(DNSChoice.init) ?? .cloudflare
        if let data = d.data(forKey: "sites"), let saved = try? JSONDecoder().decode([SiteEntry].self, from: data) {
            sites = saved
        } else {
            sites = ["discord.com", "discord.gg", "discordapp.com", "roblox.com", "wattpad.com"]
                .map { SiteEntry(domain: $0) }
        }
        Task { await loadManager() }
    }

    private func save() {
        let d = AppGroup.defaults
        d.set(presetID, forKey: "presetID")
        d.set(scope.rawValue, forKey: "scope")
        d.set(dns.rawValue, forKey: "dns")
        d.set(try? JSONEncoder().encode(sites), forKey: "sites")
    }

    // MARK: - The switch

    func toggle() {
        Task { isOn ? await stop() : await start() }
    }

    func start() async {
        state = .starting
        do {
            try writeConfig()
            let manager = try await preparedManager()
            try manager.connection.startVPNTunnel()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        manager?.connection.stopVPNTunnel()
    }

    /// A new strategy, scope, or DNS applies on the next start; restart now if on.
    func restartIfRunning() {
        guard state == .running else { return }
        restartPending = true
        manager?.connection.stopVPNTunnel()
    }

    private func writeConfig() throws {
        let include = includeSites.filter(\.isEnabled).map(\.domain)
        let exclude = excludeSites.filter(\.isEnabled).map(\.domain)
        try Domains.fileContents(include).write(to: AppGroup.hostlistURL, atomically: true, encoding: .utf8)
        try Domains.fileContents(exclude).write(to: AppGroup.excludeURL, atomically: true, encoding: .utf8)
        try TunnelConfig(strategy: preset.arguments, scope: scope, dns: dns,
                         hasHostlist: !include.isEmpty, hasExcludes: !exclude.isEmpty).save()
    }

    // MARK: - The VPN configuration

    private func loadManager() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        if let existing = managers.first { adopt(existing) }
    }

    /// The saved VPN configuration, created the first time. Saving it the first
    /// time shows iOS's "Add VPN Configurations" prompt.
    private func preparedManager() async throws -> NETunnelProviderManager {
        let manager = manager ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppGroup.tunnelBundleID
        proto.serverAddress = String(localized: "On this iPhone")
        manager.protocolConfiguration = proto
        manager.localizedDescription = "Zapret"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        adopt(manager)
        return manager
    }

    private func adopt(_ manager: NETunnelProviderManager) {
        guard self.manager !== manager else { return }
        self.manager = manager
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusChanged() }
        }
        statusChanged()
    }

    private func statusChanged() {
        guard let connection = manager?.connection else { return }
        switch connection.status {
        case .connected:
            state = .running
            startedAt = connection.connectedDate ?? .now
            startLogTail()
        case .connecting, .reasserting:
            state = .starting
        case .disconnecting:
            state = .stopping
        case .disconnected, .invalid:
            startedAt = nil
            stopLogTail()
            if restartPending {
                restartPending = false
                Task { await start() }
                return
            }
            if state == .starting {
                connection.fetchLastDisconnectError { [weak self] error in
                    Task { @MainActor in
                        self?.state = .failed(error?.localizedDescription ?? String(localized: "The tunnel stopped."))
                        self?.readTunnelLog()
                    }
                }
            } else if case .failed = state {
            } else {
                state = .stopped
            }
        @unknown default:
            break
        }
    }

    // MARK: - Log and counts

    private func startLogTail() {
        logOffset = 0
        logLines = []
        connections = 0
        hostsSeen = []
        readLog()
        logTimer?.invalidate()
        logTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readLog() }
        }
    }

    private func stopLogTail() {
        logTimer?.invalidate()
        logTimer = nil
        readTunnelLog()
    }

    /// Reads what tpws wrote since the last call.
    func readLog() {
        readTunnelLog()
        guard let handle = try? FileHandle(forReadingFrom: AppGroup.logURL) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < logOffset { logOffset = 0 }
        try? handle.seek(toOffset: logOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }
        // Keep a partial last line for the next read.
        guard let lastNewline = text.lastIndex(of: "\n") else { return }
        let complete = text[..<lastNewline]
        logOffset += UInt64(complete.utf8.count + 1)
        var seen = Set(hostsSeen)
        for raw in complete.split(separator: "\n") {
            let line = LogLine(id: nextLineID, text: String(raw))
            nextLineID += 1
            if line.kind == .connection { connections += 1 }
            if let host = line.host, seen.insert(host).inserted { hostsSeen.insert(host, at: 0) }
            logLines.append(line)
        }
        if logLines.count > 2000 { logLines.removeFirst(logLines.count - 2000) }
    }

    private func readTunnelLog() {
        guard let text = try? String(contentsOf: AppGroup.tunnelLogURL, encoding: .utf8) else { return }
        tunnelLog = text.split(separator: "\n").map(String.init)
    }

    func clearLog() {
        logLines = []
    }

    // MARK: - Sites

    /// Adds every domain in the pasted text. Returns how many were new.
    @discardableResult
    func addSites(_ text: String, excluded: Bool) -> Int {
        let existing = Set(sites.filter { $0.isExcluded == excluded }.map(\.domain))
        let new = Domains.parseList(text).filter { !existing.contains($0) }
        sites += new.map { SiteEntry(domain: $0, isExcluded: excluded) }
        if !new.isEmpty { restartIfRunning() }
        return new.count
    }

    func removeSites(_ ids: Set<String>) {
        sites.removeAll { ids.contains($0.id) }
        restartIfRunning()
    }

    func toggleSite(_ entry: SiteEntry) {
        guard let i = sites.firstIndex(of: entry) else { return }
        sites[i].isEnabled.toggle()
        restartIfRunning()
    }
}
