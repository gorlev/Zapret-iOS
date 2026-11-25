import Foundation

/// A strategy a person made, stored as tpws flags in the App Group defaults.
public struct CustomStrategy: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var commandLine: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, commandLine: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.commandLine = commandLine
        self.createdAt = createdAt
    }

    public var options: StrategyOptions { StrategyOptions(commandLine: commandLine) }
    public var arguments: [String] { CommandLineWords.split(commandLine) }
    public var selection: StrategySelection { .custom(id) }

    /// The defaults key the list is saved under.
    public static let defaultsKey = "customStrategies"

    public static func load(from defaults: UserDefaults = AppGroup.defaults) -> [CustomStrategy] {
        guard let data = defaults.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([CustomStrategy].self, from: data) else { return [] }
        return saved
    }

    public static func save(_ strategies: [CustomStrategy], to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(try? JSONEncoder().encode(strategies), forKey: defaultsKey)
    }
}

/// Which strategy is in use: a built-in preset or one of the person's own.
///
/// Stored as a string under the old `presetID` key: a preset is its plain id
/// (so values saved before custom strategies existed still read), a custom
/// strategy is "custom:<UUID>".
public enum StrategySelection: Hashable, Sendable {
    case preset(String)
    case custom(UUID)

    static let customPrefix = "custom:"

    public init(storedID: String) {
        if storedID.hasPrefix(Self.customPrefix),
           let uuid = UUID(uuidString: String(storedID.dropFirst(Self.customPrefix.count))) {
            self = .custom(uuid)
        } else {
            self = .preset(storedID)
        }
    }

    public var storedID: String {
        switch self {
        case .preset(let id): id
        case .custom(let uuid): Self.customPrefix + uuid.uuidString
        }
    }

    public static var `default`: StrategySelection { .preset(Preset.defaultID) }
}

/// A strategy's name and flags, whichever kind it is.
public struct ResolvedStrategy: Equatable, Sendable {
    public var name: String
    public var symbol: String
    public var arguments: [String]

    /// The chosen strategy. Falls back to the default preset when the chosen
    /// preset is unknown or the chosen custom strategy was deleted.
    public init(_ selection: StrategySelection, custom: [CustomStrategy]) {
        switch selection {
        case .custom(let id):
            if let strategy = custom.first(where: { $0.id == id }) {
                self.init(name: strategy.name, symbol: "person.crop.circle", arguments: strategy.arguments)
                return
            }
        case .preset(let id):
            if let preset = Preset.with(id: id) {
                self.init(name: preset.name, symbol: preset.symbol, arguments: preset.arguments)
                return
            }
        }
        let preset = Preset.with(id: Preset.defaultID) ?? Preset.all[0]
        self.init(name: preset.name, symbol: preset.symbol, arguments: preset.arguments)
    }

    public init(name: String, symbol: String, arguments: [String]) {
        self.name = name
        self.symbol = symbol
        self.arguments = arguments
    }
}

extension Preset {
    /// The preset's flags as form options, for Duplicate.
    public var options: StrategyOptions { StrategyOptions(commandLine: commandLine) }
}
