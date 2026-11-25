import Foundation
import NetworkExtension

/// Turns the bypass on and off without the app's screens: the App Intents, the
/// Control Center control and the widget all go through here. It loads the saved
/// VPN configuration and calls start or stop. It needs the last run's TunnelConfig
/// in the App Group; before the first run there is none and the app must open once.
@MainActor
enum BypassControl {
    enum Failure: LocalizedError {
        case needsSetup
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .needsSetup: String(localized: "Open Zapret and turn the bypass on once first.")
            case .failed(let message): message
            }
        }
    }

    /// The saved Zapret VPN configuration, or nil before the first start.
    static func loadManager() async -> NETunnelProviderManager? {
        let all = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        return all.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppGroup.tunnelBundleID }
    }

    static func isOn(_ manager: NETunnelProviderManager?) -> Bool {
        switch manager?.connection.status {
        case .connected, .connecting, .reasserting: true
        default: false
        }
    }

    /// Whether the bypass is on or starting right now.
    static func isOn() async -> Bool { isOn(await loadManager()) }

    static func start() async throws {
        guard let manager = await loadManager(), FileManager.default.fileExists(atPath: AppGroup.configURL.path) else {
            throw Failure.needsSetup
        }
        if isOn(manager) { return }
        do {
            // The settings may have changed since the last start.
            var config = try TunnelConfig.load()
            config.verbose = SharedPrefs.verboseLog
            config.shareOnNetwork = SharedPrefs.shareOnNetwork
            try config.save()
            configureOnDemand(manager)
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
    }

    /// Stops the bypass. With "Keep the bypass on", iOS would reconnect right away,
    /// so the on-demand rule goes off first and comes back at the next start.
    static func stop(_ known: NETunnelProviderManager? = nil) async {
        let found = await loadManager()
        guard let manager = known ?? found else { return }
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            try? await manager.saveToPreferences()
        }
        manager.connection.stopVPNTunnel()
    }

    /// The "Keep the bypass on" rule: connect on any network. It is armed only while
    /// the bypass runs, so turning it on in Settings does not start the bypass.
    static func configureOnDemand(_ manager: NETunnelProviderManager) {
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        manager.onDemandRules = [rule]
        manager.isOnDemandEnabled = SharedPrefs.keepOn
    }

    /// "Keep the bypass on" changed in Settings.
    static func keepOnChanged() async {
        guard let manager = await loadManager() else { return }
        configureOnDemand(manager)
        manager.isOnDemandEnabled = SharedPrefs.keepOn && isOn(manager)
        try? await manager.saveToPreferences()
    }
}
