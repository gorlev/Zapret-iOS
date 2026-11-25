import Foundation

/// Which sites tpws changes traffic for.
public enum Scope: String, CaseIterable, Sendable, Codable {
    case allSites, listOnly
}

/// How the device looks up site names while the bypass is on.
public enum DNSChoice: String, CaseIterable, Sendable, Codable, Identifiable {
    /// Encrypted DNS (DNS over HTTPS) at Cloudflare. Gets past DNS blocks, and its
    /// traffic is TCP, so it goes through the tunnel like everything else.
    case cloudflare
    /// Encrypted DNS at Google.
    case google

    public var id: String { rawValue }
}

/// The files and settings the app and the tunnel extension share through the App Group.
public enum AppGroup {
    public static let id = "group.com.gorlev.zapretios"
    public static let tunnelBundleID = "com.gorlev.zapretios.tunnel"

    public static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.temporaryDirectory
    }

    public static var configURL: URL { container.appending(path: "tunnel-config.json") }
    public static var hostlistURL: URL { container.appending(path: "hostlist.txt") }
    public static var excludeURL: URL { container.appending(path: "exclude.txt") }
    public static var logURL: URL { container.appending(path: "tpws.log") }
    /// Lines the extension itself writes: start, stop, errors.
    public static var tunnelLogURL: URL { container.appending(path: "tunnel.log") }

    public static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// What the app hands the tunnel extension before it starts.
public struct TunnelConfig: Codable, Equatable, Sendable {
    /// tpws strategy flags, like ["--tlsrec=sniext+1", "--split-pos=1,midsld"].
    public var strategy: [String]
    public var scope: Scope
    public var dns: DNSChoice
    /// Whether the include list has any entries (tpws refuses an empty hostlist file).
    public var hasHostlist: Bool
    public var hasExcludes: Bool

    public init(strategy: [String], scope: Scope, dns: DNSChoice, hasHostlist: Bool, hasExcludes: Bool) {
        self.strategy = strategy
        self.scope = scope
        self.dns = dns
        self.hasHostlist = hasHostlist
        self.hasExcludes = hasExcludes
    }

    /// The port tpws listens on inside the extension; hev-socks5-tunnel connects to it.
    public static let socksPort = 10808

    /// The full tpws argument list, starting with the program name.
    public var tpwsArguments: [String] {
        var out = ["tpws", "--socks", "--bind-addr=127.0.0.1", "--port=\(Self.socksPort)",
                   "--debug=@\(AppGroup.logURL.path)"]
        // My list with nothing in it: tpws only passes traffic through.
        if scope == .listOnly, !hasHostlist { return out }
        var lists: [String] = []
        if scope == .listOnly, hasHostlist { lists.append("--hostlist=\(AppGroup.hostlistURL.path)") }
        if hasExcludes { lists.append("--hostlist-exclude=\(AppGroup.excludeURL.path)") }
        // Lists belong to a desync profile: every profile (split at --new) gets them.
        var profile: [String] = []
        var profiles: [[String]] = []
        for arg in strategy {
            if arg == "--new" { profiles.append(profile); profile = [] } else { profile.append(arg) }
        }
        profiles.append(profile)
        for (i, p) in profiles.enumerated() {
            if i > 0 { out.append("--new") }
            out += lists + p
        }
        return out
    }

    public func save() throws {
        try JSONEncoder().encode(self).write(to: AppGroup.configURL, options: .atomic)
    }

    public static func load() throws -> TunnelConfig {
        try JSONDecoder().decode(TunnelConfig.self, from: Data(contentsOf: AppGroup.configURL))
    }
}

extension Preset {
    /// The strategy flags, split on spaces.
    public var arguments: [String] { commandLine.split(separator: " ").map(String.init) }
}
