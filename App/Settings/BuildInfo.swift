import Foundation

/// Versions of the engines inside the app. Update these when Vendor/zapret/COMMIT
/// or Vendor/hev-socks5-tunnel/COMMIT change.
enum BuildInfo {
    static let zapretCommit = "1e1d1e24c2ad5f9def2825e2eac7a89979a8a023"
    static let hevCommit = "867e1e59dcf30ed75c0ee840991e441539fafb92"

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
