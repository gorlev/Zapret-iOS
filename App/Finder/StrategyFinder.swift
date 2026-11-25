import Foundation
import Observation

/// Tries strategies against one or more sites, like ZapretMac's StrategyFinder,
/// but one at a time: tpws runs inside the tunnel extension and starts once per
/// process, so every try restarts the tunnel with its flags (AppModel.runTrial)
/// and opens the sites through it. The user's strategy and on/off state come
/// back when the scan ends or is stopped.
@Observable
final class StrategyFinder {
    /// One site opened without any bypass.
    struct Direct: Identifiable, Equatable {
        let site: String
        let outcome: FinderProbe.Outcome
        var id: String { site }
    }

    /// What one site's block looks like (S-101), found before the tries start.
    struct Diagnosis: Identifiable, Equatable {
        let site: String
        let kind: BlockKind
        var id: String { site }
    }

    enum Phase: Equatable {
        case idle
        /// Opening the sites without the bypass and finding the kind of block.
        case diagnosing
        case trying
        /// Putting the user's strategy and on/off state back.
        case restoring
        case finished, stopped
    }

    nonisolated struct TryResult: Sendable {
        var sites: [SiteAttempt]
        var versions: [VersionResult] = []
    }

    private(set) var phase: Phase = .idle
    private(set) var trials: [Trial] = []
    private(set) var direct: [Direct] = []
    private(set) var diagnoses: [Diagnosis] = []
    private(set) var sites: [String] = []
    private(set) var depth: ScanDepth = .quick
    private(set) var versions: [TLSVersion] = []
    private(set) var repeats = 1
    private var task: Task<Void, Never>?

    var isRunning: Bool { phase == .diagnosing || phase == .trying || phase == .restoring }
    var ranked: [Trial] { Trial.ranked(trials) }
    var finishedCount: Int { trials.filter(\.isFinished).count }
    var workingCount: Int { trials.filter(\.works).count }
    /// The try now running, counted from 1.
    var currentNumber: Int? { trials.firstIndex { $0.status == .testing }.map { $0 + 1 } }
    var site: String { sites.joined(separator: ", ") }

    /// The strategies a scan tries: the built-in ones, or blockcheck's matrix
    /// for the first address (HTTP or HTTPS set).
    static func strategies(for urls: [URL], depth: ScanDepth) -> [(id: String, name: String, arguments: [String])] {
        switch depth {
        case .quick:
            Preset.all.map { (id: $0.id, name: $0.name, arguments: $0.arguments) }
        case .thorough:
            urls.first.map { ScanPlan.tries(for: $0).map { (id: $0.id, name: $0.name, arguments: $0.arguments) } } ?? []
        }
    }

    /// Every strategy is tried on every site; `timeout` is how long each site may take.
    /// A thorough scan of https:// sites tries TLS 1.3 and TLS 1.2 separately;
    /// with `repeats` above 1 a try works only if every repeat works.
    func start(urls: [URL], depth: ScanDepth, repeats: Int, model: AppModel) {
        guard !urls.isEmpty, !isRunning else { return }
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        let https = urls.allSatisfy { $0.scheme?.lowercased() == "https" }
        let versions: [TLSVersion] = depth == .thorough && https ? TLSVersion.allCases : []
        let repeats = depth == .thorough ? max(1, repeats) : 1
        let timeout: TimeInterval = depth == .thorough ? 6 : 8
        sites = hosts
        self.depth = depth
        self.versions = versions
        self.repeats = repeats
        trials = Self.strategies(for: urls, depth: depth).map { Trial(id: $0.id, name: $0.name, arguments: $0.arguments) }
        direct = []
        diagnoses = []
        phase = .diagnosing
        task = Task {
            await model.beginTrials()
            await diagnose(urls: urls, hosts: hosts, timeout: timeout)
            if !Task.isCancelled {
                phase = .trying
                await tryAll(urls: urls, timeout: timeout, versions: versions, repeats: repeats, model: model)
            }
            let cancelled = Task.isCancelled
            phase = .restoring
            // A new task is not cancelled, so the restore always runs to the end.
            await Task { await model.endTrials() }.value
            for i in trials.indices where trials[i].status == .testing { trials[i].status = .waiting }
            phase = cancelled ? .stopped : .finished
        }
    }

    /// Stops after the current step; the user's settings are then put back.
    func stop() {
        task?.cancel()
    }

    private func diagnose(urls: [URL], hosts: [String], timeout: TimeInterval) async {
        async let dns = Self.checkDNSAll(hosts)
        let outcomes = await FinderProbe.fetchAll(urls, timeout: timeout)
        let dnsResults = await dns
        guard !Task.isCancelled else { return }
        direct = zip(hosts, outcomes).map { Direct(site: $0, outcome: $1) }
        let kinds = await Self.diagnoseAll(dnsResults, opens: outcomes.map(\.isOK))
        guard !Task.isCancelled else { return }
        diagnoses = zip(hosts, kinds).map { Diagnosis(site: $0, kind: $1) }
    }

    private func tryAll(urls: [URL], timeout: TimeInterval, versions: [TLSVersion], repeats: Int, model: AppModel) async {
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        for index in trials.indices {
            guard !Task.isCancelled else { return }
            trials[index].status = .testing
            do {
                try await model.runTrial(arguments: trials[index].arguments)
            } catch is CancellationError {
                trials[index].status = .waiting
                return
            } catch {
                guard !Task.isCancelled else { trials[index].status = .waiting; return }
                trials[index].finish(with: hosts.map { SiteAttempt(site: $0, result: .fails(error.localizedDescription)) })
                continue
            }
            let result = await Self.measure(urls: urls, timeout: timeout, versions: versions, repeats: repeats)
            guard !Task.isCancelled else { trials[index].status = .waiting; return }
            if result.versions.isEmpty { trials[index].finish(with: result.sites) } else { trials[index].finish(versions: result.versions) }
        }
    }

    /// Opens every site through the running trial, with a hard limit on top of
    /// URLSession's own timeouts, so a row never stays on "Testing…".
    @concurrent nonisolated static func measure(urls: [URL], timeout: TimeInterval, versions: [TLSVersion],
                                                repeats: Int) async -> TryResult {
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        let deadline = Double(repeats) * (timeout + 2) + 2
        return await withTaskGroup(of: TryResult?.self) { group in
            group.addTask { await runRepeats(urls: urls, timeout: timeout, versions: versions, repeats: repeats) }
            group.addTask {
                try? await Task.sleep(for: .seconds(deadline))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if let first { return first }
            let timedOut = hosts.map { SiteAttempt(site: $0, result: .fails(String(localized: "Timed out"))) }
            return TryResult(sites: timedOut, versions: versions.map { VersionResult(version: $0, sites: timedOut) })
        }
    }

    /// Every repeat in turn, stopping at the first one where a site fails;
    /// TLS versions side by side.
    @concurrent nonisolated private static func runRepeats(urls: [URL], timeout: TimeInterval,
                                                           versions: [TLSVersion], repeats: Int) async -> TryResult {
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        @Sendable func repeated(_ tls: TLSVersion?) async -> [[SiteAttempt]] {
            var runs: [[SiteAttempt]] = []
            for _ in 0..<repeats {
                let outcomes = await FinderProbe.fetchAll(urls, timeout: timeout, tls: tls)
                let attempts = zip(hosts, outcomes).map { host, outcome in
                    switch outcome {
                    case .ok(_, let ms): SiteAttempt(site: host, result: .opens(milliseconds: ms))
                    case .failed(let reason): SiteAttempt(site: host, result: .fails(reason))
                    }
                }
                runs.append(attempts)
                if Task.isCancelled || attempts.contains(where: { !$0.opens }) { break }
            }
            return runs
        }
        guard !versions.isEmpty else { return TryResult(sites: Trial.combine(repeats: await repeated(nil))) }
        let results = await withTaskGroup(of: (Int, VersionResult).self) { group in
            for (i, version) in versions.enumerated() {
                group.addTask { (i, VersionResult(version: version, repeats: await repeated(version))) }
            }
            var out: [(Int, VersionResult)] = []
            for await item in group { out.append(item) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return TryResult(sites: [], versions: results)
    }

    /// The sites' DNS checks, all at once, in the given order.
    @concurrent nonisolated static func checkDNSAll(_ hosts: [String]) async -> [BlockCheck.DNSResult] {
        await withTaskGroup(of: (Int, BlockCheck.DNSResult).self) { group in
            for (i, host) in hosts.enumerated() { group.addTask { (i, await BlockCheck.checkDNS(host: host)) } }
            var out = [BlockCheck.DNSResult](repeating: .init(verdict: .unknown, publicAddresses: [], system: nil), count: hosts.count)
            for await (i, result) in group { out[i] = result }
            return out
        }
    }

    /// Every site's verdict, all at once, in the given order.
    @concurrent nonisolated static func diagnoseAll(_ dns: [BlockCheck.DNSResult], opens: [Bool]) async -> [BlockKind] {
        await withTaskGroup(of: (Int, BlockKind).self) { group in
            for (i, result) in dns.enumerated() {
                let ok = i < opens.count && opens[i]
                group.addTask { (i, await BlockCheck.finish(result, opensDirectly: ok)) }
            }
            var out = [BlockKind](repeating: .dpi, count: dns.count)
            for await (i, kind) in group { out[i] = kind }
            return out
        }
    }

    #if DEBUG
    /// Sample states for screenshots in the simulator, where the VPN does not run.
    func loadSample(_ sample: FinderSample) {
        sites = ["discord.com"]
        depth = .thorough
        versions = TLSVersion.allCases
        let tries = ScanPlan.https
        trials = tries.map { Trial(id: $0.id, name: $0.name, arguments: $0.arguments) }
        direct = [Direct(site: "discord.com", outcome: .failed(String(localized: "Connection reset")))]
        diagnoses = [Diagnosis(site: "discord.com", kind: .dpi)]
        func both(_ i: Int, _ ms13: Int, _ ms12: Int?) {
            let v13 = VersionResult(version: .tls13, sites: [SiteAttempt(site: "discord.com", result: .opens(milliseconds: ms13))])
            let v12 = VersionResult(version: .tls12, sites: [SiteAttempt(site: "discord.com", result: ms12.map { .opens(milliseconds: $0) } ?? .fails("Connection reset"))])
            trials[i].finish(versions: [v13, v12])
        }
        func fail(_ i: Int) {
            let r = [SiteAttempt(site: "discord.com", result: .fails(String(localized: "Connection reset")))]
            trials[i].finish(versions: [VersionResult(version: .tls13, sites: r), VersionResult(version: .tls12, sites: r)])
        }
        switch sample {
        case .start:
            trials = []
            direct = []
            diagnoses = []
            phase = .idle
        case .progress:
            fail(0); both(1, 312, 340); fail(2); both(3, 288, nil); fail(4)
            trials[5].status = .testing
            phase = .trying
        case .verdict:
            for i in trials.indices { fail(i) }
            both(1, 312, 340); both(3, 288, nil); both(13, 402, 455); both(22, 251, 270); both(25, 530, 560); both(27, 297, 318)
            phase = .finished
        }
    }
    #endif
}
