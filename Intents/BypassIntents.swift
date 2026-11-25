import AppIntents

/// What Shortcuts, Siri, and the Action button can do. They never open the app;
/// before the bypass has run once there are no settings to start with, and they say so.
struct TurnBypassOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Bypass On"
    static let description = IntentDescription("Turns the Zapret bypass on.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await BypassControl.start()
        return .result(dialog: "Bypass is on.")
    }
}

struct TurnBypassOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Bypass Off"
    static let description = IntentDescription("Turns the Zapret bypass off.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await BypassControl.stop()
        return .result(dialog: "Bypass is off.")
    }
}

struct ToggleBypassIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Bypass"
    static let description = IntentDescription("Turns the Zapret bypass on if it is off, and off if it is on.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if await BypassControl.isOn() {
            await BypassControl.stop()
            return .result(dialog: "Bypass is off.")
        }
        try await BypassControl.start()
        return .result(dialog: "Bypass is on.")
    }
}

/// The Control Center control's switch.
struct SetBypassIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Bypass"

    @Parameter(title: "On")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        if value { try await BypassControl.start() } else { await BypassControl.stop() }
        return .result()
    }
}
