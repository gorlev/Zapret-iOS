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
    // TEMPORARY (debug): how often tpws changed a packet. Remove with DebugTamperCard.swift.
    private(set) var debugSplits = 0
    private(set) var debugTLSRecords = 0

    /// The chosen strategy as stored: a preset id or "custom:<UUID>". Use `selection`.
    var presetID: String { didSet { save(); restartIfRunning() } }
    /// Strategies the person made (AppModel+Strategies.swift).
    var customStrategies: [CustomStrategy] { didSet { CustomStrategy.save(customStrategies) } }
    var scope: Scope { didSet { save(); restartIfRunning() } }
    var dns: DNSChoice { didSet { save(); restartIfRunning() } }
    var sites: [SiteEntry] { didSet { save() } }
    /// Subscriptions, the automatic list, and undo for the Sites page.
    let lists = SiteLists()

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
        customStrategies = CustomStrategy.load(from: d)
        scope = d.string(forKey: "scope").flatMap(Scope.init) ?? .allSites
        dns = d.string(forKey: "dns").flatMap(DNSChoice.init) ?? .cloudflare
        if let data = d.data(forKey: "sites"), let saved = try? JSONDecoder().decode([SiteEntry].self, from: data) {
            sites = saved
        } else {
            sites = ["discord.com", "discord.gg", "discordapp.com", "roblox.com", "wattpad.com"]
                .map { SiteEntry(domain: $0) }
        }
        lists.onChange = { [weak self] in self?.restartIfRunning() }
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
        if let trialArguments { return try writeTrialConfig(trialArguments) }
        let files = try writeListFiles()
        try TunnelConfig(strategy: activeStrategy.arguments, scope: scope, dns: dns,
                         hasHostlist: files.hasHostlist, hasExcludes: files.hasExcludes, lists: files.lists).save()
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
            // Find a Strategy reports a trial that did not start itself.
            if state == .starting && trialArguments == nil {
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
        debugSplits = 0
        debugTLSRecords = 0
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
            if line.text.hasPrefix("multisplit pos:") { debugSplits += 1 }
            if line.text.hasPrefix("making 2 TLS records") { debugTLSRecords += 1 }
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

    /// Adds every domain and IP address or range in the pasted text. Returns how many were new.
    @discardableResult
    func addSites(_ text: String, excluded: Bool) -> Int {
        let existing = Set(sites.filter { $0.isExcluded == excluded }.map(\.domain))
        let routed = IPRanges.route(text)
        let new = (routed.domains + routed.addresses).filter { !existing.contains($0) }
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

    // MARK: - Find a Strategy trials

    /// The flags a Find a Strategy trial runs in place of the chosen strategy; nil outside trials.
    private var trialArguments: [String]?
    /// Whether the bypass was on before the trials began; nil outside trials.
    private var onBeforeTrials: Bool?

    enum TrialError: LocalizedError {
        case didNotStart(String), timedOut

        var errorDescription: String? {
            switch self {
            case .didNotStart(let reason): reason
            case .timedOut: String(localized: "The tunnel did not start in time")
            }
        }
    }

    /// Stops the tunnel before Find a Strategy opens the sites directly, and
    /// remembers whether the bypass was on, for `endTrials()`.
    func beginTrials() async {
        if onBeforeTrials == nil { onBeforeTrials = isOn }
        restartPending = false
        await stopTunnelAndWait()
    }

    /// Restarts the tunnel with `arguments` in place of the chosen strategy (every
    /// site, no lists) and returns once it is connected, so the app's own requests
    /// go through tpws with these flags. tpws starts once per extension process,
    /// so every trial is a full stop and start (2-4 s).
    func runTrial(arguments: [String], timeout: Duration = .seconds(15)) async throws {
        if onBeforeTrials == nil { onBeforeTrials = isOn }
        try Task.checkCancellation()
        await stopTunnelAndWait()
        try Task.checkCancellation()
        trialArguments = arguments
        state = .starting
        try writeConfig()
        let manager = try await trialManager()
        try manager.connection.startVPNTunnel()
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        let grace = clock.now + .seconds(3)
        var seenConnecting = false
        while clock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            switch manager.connection.status {
            case .connected:
                return
            case .connecting, .reasserting:
                seenConnecting = true
            case .disconnected, .invalid:
                if seenConnecting || clock.now > grace {
                    throw TrialError.didNotStart(await Self.lastDisconnectReason(manager.connection))
                }
            default:
                break
            }
        }
        throw TrialError.timedOut
    }

    /// Puts back the chosen strategy and the on/off state from before the trials,
    /// and returns once the bypass is back (or off).
    func endTrials() async {
        guard let wasOn = onBeforeTrials else { return }
        onBeforeTrials = nil
        await stopTunnelAndWait()
        trialArguments = nil
        state = .stopped
        guard wasOn else { return }
        await start()
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline, state == .starting { await Self.pause(.milliseconds(200)) }
    }

    /// Find a Strategy's "Use": selects the built-in strategy with these flags.
    /// Returns whether a built-in strategy had them.
    @discardableResult
    func adoptFoundStrategy(name: String, arguments: [String]) -> Bool {
        if let preset = Preset.all.first(where: { $0.arguments == arguments }) {
            choose(.preset(preset.id))
            return true
        }
        let commandLine = arguments.joined(separator: " ")
        if let existing = customStrategies.first(where: { $0.commandLine == commandLine }) {
            choose(existing.selection)
            return true
        }
        let strategy = CustomStrategy(name: name, commandLine: commandLine)
        customStrategies.append(strategy)
        choose(strategy.selection)
        return true
    }

    private func writeTrialConfig(_ arguments: [String]) throws {
        try TunnelConfig(strategy: arguments, scope: .allSites, dns: dns, hasHostlist: false, hasExcludes: false).save()
    }

    /// The saved VPN configuration, without saving it again when it is already set up.
    private func trialManager() async throws -> NETunnelProviderManager {
        if let manager, manager.isEnabled { return manager }
        return try await preparedManager()
    }

    private func stopTunnelAndWait() async {
        guard let connection = manager?.connection else { return }
        let stopped: (NEVPNStatus) -> Bool = { $0 == .disconnected || $0 == .invalid }
        guard !stopped(connection.status) else { return }
        connection.stopVPNTunnel()
        let deadline = ContinuousClock.now + .seconds(8)
        while ContinuousClock.now < deadline, !stopped(connection.status) { await Self.pause(.milliseconds(100)) }
        // The extension quits half a second after it stops; the next start must get a new process, so a fresh tpws.
        await Self.pause(.seconds(1))
    }

    /// A wait that also runs in a cancelled task, so stopping and restoring always finish.
    private static func pause(_ duration: Duration) async {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }

    private static func lastDisconnectReason(_ connection: NEVPNConnection) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            connection.fetchLastDisconnectError { @Sendable error in
                continuation.resume(returning: error?.localizedDescription ?? String(localized: "The tunnel stopped"))
            }
        }
    }
}
