import Foundation

/// The settings the app, the tunnel extension, and the intents all read. They live
/// in the App Group's defaults; the app's Settings screen writes them.
public nonisolated enum SharedPrefs {
    public static let startOnLaunchKey = "startOnLaunch"
    public static let keepOnKey = "keepOn"
    public static let verboseLogKey = "verboseLog"
    public static let shareOnNetworkKey = "shareOnNetwork"

    /// Turn the bypass on when the app opens.
    public static var startOnLaunch: Bool { AppGroup.defaults.bool(forKey: startOnLaunchKey) }
    /// Let iOS reconnect the bypass by itself (on-demand rule).
    public static var keepOn: Bool { AppGroup.defaults.bool(forKey: keepOnKey) }
    /// Log every connection (tpws debug level 1). On by default, as on the Mac.
    public static var verboseLog: Bool { (AppGroup.defaults.object(forKey: verboseLogKey) as? Bool) ?? true }
    /// Also listen on the Wi-Fi address so other devices can use the SOCKS proxy.
    public static var shareOnNetwork: Bool { AppGroup.defaults.bool(forKey: shareOnNetworkKey) }
}
