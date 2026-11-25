import Foundation

extension AppGroup {
    /// My list's IP addresses and ranges (tpws `--ipset`).
    public static var ipsetURL: URL { container.appending(path: "ipset.txt") }
    /// Never Touch's IP addresses and ranges (tpws `--ipset-exclude`).
    public static var ipsetExcludeURL: URL { container.appending(path: "ipset-exclude.txt") }
    /// The file tpws appends sites to with `--hostlist-auto`.
    public static var autoHostlistURL: URL { container.appending(path: "autohostlist.txt") }
    /// Downloaded subscription lists, one cleaned file per list.
    public static var listsFolder: URL { container.appending(path: "lists", directoryHint: .isDirectory) }

    /// A path relative to the App Group container, as `TunnelLists` stores it.
    public static func url(relative path: String) -> URL { container.appending(path: path) }
}

/// The list files beyond My list's and Never Touch's hostlists: subscribed
/// lists, IP ranges, and the automatic list. Each file is handed to tpws as
/// its own flag, so the extension never reads or joins big lists itself
/// (tpws loads each file once, however many profiles name it).
/// Paths are relative to the App Group container.
public struct TunnelLists: Codable, Equatable, Sendable {
    /// More `--hostlist` files: subscribed domain lists.
    public var hostlists: [String] = []
    /// More `--hostlist-exclude` files.
    public var hostlistExcludes: [String] = []
    /// `--ipset` files: My list's addresses and subscribed IP lists.
    public var ipsets: [String] = []
    /// `--ipset-exclude` files.
    public var ipsetExcludes: [String] = []
    /// tpws `--hostlist-auto` into `AppGroup.autoHostlistURL` (My list only).
    public var autoHostlist = false

    public init(hostlists: [String] = [], hostlistExcludes: [String] = [], ipsets: [String] = [],
                ipsetExcludes: [String] = [], autoHostlist: Bool = false) {
        self.hostlists = hostlists
        self.hostlistExcludes = hostlistExcludes
        self.ipsets = ipsets
        self.ipsetExcludes = ipsetExcludes
        self.autoHostlist = autoHostlist
    }

    /// A site that fails this many times within `autoFailTime` seconds is added.
    public static let autoFailThreshold = 3
    public static let autoFailTime = 60

    public static var autoHostlistArguments: [String] {
        ["--hostlist-auto=\(AppGroup.autoHostlistURL.path)",
         "--hostlist-auto-fail-threshold=\(autoFailThreshold)",
         "--hostlist-auto-fail-time=\(autoFailTime)"]
    }
}
