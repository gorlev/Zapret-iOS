import Foundation
import Observation
import WidgetKit

/// The Settings switches, saved in the App Group so the tunnel extension and the
/// intents read the same values (see SharedPrefs).
@Observable
final class AppPrefs {
    static let shared = AppPrefs()

    var startOnLaunch: Bool { didSet { AppGroup.defaults.set(startOnLaunch, forKey: SharedPrefs.startOnLaunchKey) } }
    var keepOn: Bool { didSet { AppGroup.defaults.set(keepOn, forKey: SharedPrefs.keepOnKey) } }
    var verboseLog: Bool { didSet { AppGroup.defaults.set(verboseLog, forKey: SharedPrefs.verboseLogKey) } }
    var shareOnNetwork: Bool { didSet { AppGroup.defaults.set(shareOnNetwork, forKey: SharedPrefs.shareOnNetworkKey) } }

    private init() {
        startOnLaunch = SharedPrefs.startOnLaunch
        keepOn = SharedPrefs.keepOn
        verboseLog = SharedPrefs.verboseLog
        shareOnNetwork = SharedPrefs.shareOnNetwork
    }
}

/// Keeps what the widget and the Control Center control show current.
enum WidgetSync {
    static func update(_ model: AppModel) {
        AppGroup.defaults.set(model.preset.name, forKey: "strategyName")
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}
