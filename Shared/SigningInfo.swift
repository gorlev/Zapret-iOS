import Foundation

/// What the app was actually signed with. A copy re-signed by a sideloading
/// tool can have a different App Group and bundle IDs than the ones in
/// project.yml, so these are read at run time.
nonisolated enum SigningInfo {
    /// The first App Group in the embedded provisioning profile's entitlements.
    static let appGroup: String? = {
        guard let entitlements = profileEntitlements(at: Bundle.main.bundleURL),
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return nil }
        return groups.first { !$0.contains("*") }
    }()

    /// The bundle ID of ZapretTunnel.appex inside the app, from the app, the
    /// tunnel, or the widget.
    static let tunnelBundleID: String? = {
        guard let app = containingAppURL else { return nil }
        let tunnel = app.appending(path: "PlugIns/ZapretTunnel.appex")
        return Bundle(url: tunnel)?.bundleIdentifier
    }()

    /// The .app bundle: Bundle.main itself, or two levels up from an .appex in PlugIns.
    private static var containingAppURL: URL? {
        let url = Bundle.main.bundleURL
        if url.pathExtension == "appex" { return url.deletingLastPathComponent().deletingLastPathComponent() }
        return url.pathExtension == "app" ? url : nil
    }

    /// The Entitlements dictionary of `embedded.mobileprovision` in a bundle.
    /// The file is a signed CMS envelope with the profile's XML plist inside in
    /// plain text, so the plist is cut out and parsed without Security APIs.
    static func profileEntitlements(at bundle: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: bundle.appending(path: "embedded.mobileprovision")),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any]
        return plist?["Entitlements"] as? [String: Any]
    }
}
