import Foundation

// Copied from ZapretMacKit's Trial.swift: what one strategy did on one or more sites.

/// What happened when one site was opened through one strategy.
nonisolated struct SiteAttempt: Equatable, Sendable {
    enum Result: Equatable, Sendable {
        case opens(milliseconds: Int)
        case fails(String)
    }

    /// The site's host, as shown to the user.
    let site: String
    let result: Result

    var opens: Bool { if case .opens = result { true } else { false } }

    /// One site tried several times: it opens only if every try opened, in
    /// the slowest try's time; otherwise it fails with the first failure's reason.
    static func combine(repeats: [SiteAttempt]) -> SiteAttempt? {
        guard let first = repeats.first else { return nil }
        var slowest = 0
        for attempt in repeats {
            switch attempt.result {
            case .opens(let ms): slowest = max(slowest, ms)
            case .fails: return attempt
            }
        }
        return SiteAttempt(site: first.site, result: .opens(milliseconds: slowest))
    }
}

/// A TLS version a thorough scan tries separately, like blockcheck's
/// `--tlsv1.3` and `--tlsv1.2 --tls-max 1.2`.
nonisolated enum TLSVersion: String, CaseIterable, Sendable, Hashable {
    case tls13 = "1.3", tls12 = "1.2"

    /// "TLS 1.3".
    var name: String { "TLS \(rawValue)" }
}

/// Every site's result with one TLS version, after every repeat.
nonisolated struct VersionResult: Equatable, Sendable {
    let version: TLSVersion
    let sites: [SiteAttempt]

    init(version: TLSVersion, sites: [SiteAttempt]) {
        self.version = version
        self.sites = sites
    }

    /// Repeats of the same sites (each inner list is one repeat, sites in
    /// order) folded into one result per site.
    init(version: TLSVersion, repeats: [[SiteAttempt]]) {
        self.init(version: version, sites: Trial.combine(repeats: repeats))
    }

    /// Every site opened with this version.
    var opens: Bool { !sites.isEmpty && sites.allSatisfy(\.opens) }
}

/// The result of trying one strategy against one or more sites.
nonisolated struct Trial: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting, testing
        case works(milliseconds: Int)
        case fails(String)
    }

    /// A preset id, or "scan:<flags>" for a thorough-scan try.
    let id: String
    let name: String
    let arguments: [String]
    var status: Status = .waiting
    /// One entry per site, in the order the sites were given. Empty until the try finishes.
    var sites: [SiteAttempt] = []
    /// Thorough scans of https:// sites: the result with each TLS version.
    var versions: [VersionResult] = []

    init(id: String, name: String, arguments: [String], status: Status = .waiting) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
    }

    var works: Bool { if case .works = status { true } else { false } }
    var isFinished: Bool { status != .waiting && status != .testing }

    /// How many of the sites opened.
    var openCount: Int { sites.filter(\.opens).count }
    /// The sites that did not open, in order.
    var failedSites: [SiteAttempt] { sites.filter { !$0.opens } }
    /// Some sites opened and some did not.
    var isPartial: Bool { sites.count > 1 && openCount > 0 && openCount < sites.count }

    /// Records every site's result and the status they add up to.
    mutating func finish(with attempts: [SiteAttempt]) {
        sites = attempts
        versions = []
        status = Self.combine(attempts)
    }

    /// Records each TLS version's results. A site opens if it opened with
    /// every version, or with TLS 1.3 alone (what browsers use; see
    /// `worksOnlyWithTLS13`). Otherwise it fails, naming the version it failed with.
    mutating func finish(versions results: [VersionResult]) {
        guard let first = results.first else { return finish(with: []) }
        let joined = first.sites.indices.map { i -> SiteAttempt in
            let site = first.sites[i].site
            var slowest = 0
            var failure: (TLSVersion, String)?
            var tls13: Int?
            for result in results where i < result.sites.count {
                switch result.sites[i].result {
                case .opens(let ms):
                    slowest = max(slowest, ms)
                    if result.version == .tls13 { tls13 = ms }
                case .fails(let reason):
                    if failure == nil { failure = (result.version, reason) }
                }
            }
            if let failure {
                if let tls13 { return SiteAttempt(site: site, result: .opens(milliseconds: tls13)) }
                return SiteAttempt(site: site, result: .fails("\(failure.0.name): \(failure.1)"))
            }
            return SiteAttempt(site: site, result: .opens(milliseconds: slowest))
        }
        sites = joined
        versions = results
        status = Self.combine(joined)
    }

    /// The try works, but only because TLS 1.3 worked: TLS 1.2 was tried and failed.
    var worksOnlyWithTLS13: Bool {
        works && works(with: .tls13) == true && works(with: .tls12) == false
    }

    /// Whether the try worked with a version; nil if that version was not tried.
    func works(with version: TLSVersion) -> Bool? {
        versions.first { $0.version == version }?.opens
    }

    /// Several repeats over the same sites folded per site: a site opens only if every repeat opened.
    static func combine(repeats: [[SiteAttempt]]) -> [SiteAttempt] {
        guard let first = repeats.first else { return [] }
        return first.indices.compactMap { i in
            SiteAttempt.combine(repeats: repeats.compactMap { i < $0.count ? $0[i] : nil })
        }
    }

    /// A strategy works only if every site opens; its time is the slowest
    /// site's. Otherwise it fails with the first failing site's reason.
    static func combine(_ attempts: [SiteAttempt]) -> Status {
        var slowest = 0
        for attempt in attempts {
            switch attempt.result {
            case .opens(let ms): slowest = max(slowest, ms)
            case .fails(let reason): return .fails(reason)
            }
        }
        return attempts.isEmpty ? .waiting : .works(milliseconds: slowest)
    }

    /// Working strategies first, fastest first (every TLS version before
    /// TLS 1.3 only); then the one being tried; then waiting; failures last,
    /// those that opened more sites first. Equal ranks keep their order.
    static func ranked(_ trials: [Trial]) -> [Trial] {
        func key(_ t: Trial) -> (Int, Int) {
            switch t.status {
            case .works(let ms): (t.worksOnlyWithTLS13 ? 1 : 0, ms)
            case .testing: (2, 0)
            case .waiting: (3, 0)
            case .fails: (4, -t.openCount)
            }
        }
        return trials.enumerated()
            .sorted { a, b in
                let ka = key(a.element), kb = key(b.element)
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.element)
    }
}
