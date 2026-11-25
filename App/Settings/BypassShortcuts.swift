import AppIntents

/// The phrases Siri and Shortcuts offer without any setup.
struct BypassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TurnBypassOnIntent(), phrases: ["Turn on \(.applicationName)", "Turn \(.applicationName) bypass on"],
                    shortTitle: "Turn Bypass On", systemImageName: "power")
        AppShortcut(intent: TurnBypassOffIntent(), phrases: ["Turn off \(.applicationName)", "Turn \(.applicationName) bypass off"],
                    shortTitle: "Turn Bypass Off", systemImageName: "power.dotted")
        AppShortcut(intent: ToggleBypassIntent(), phrases: ["Toggle \(.applicationName)"],
                    shortTitle: "Toggle Bypass", systemImageName: "shield.lefthalf.filled")
    }
}
