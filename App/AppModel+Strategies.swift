import Foundation
import UIKit

/// What the strategy editor sheet is working on.
struct StrategyDraft: Identifiable {
    var id = UUID()
    /// The custom strategy being edited, or nil for a new one.
    var editing: UUID?
    var name: String
    var options: StrategyOptions

    /// A new strategy, by default the common split.
    static func new(from options: StrategyOptions = StrategyOptions(commandLine: "--split-pos=1,midsld"),
                    name: String = "") -> StrategyDraft {
        StrategyDraft(editing: nil, name: name, options: options)
    }

    static func edit(_ strategy: CustomStrategy) -> StrategyDraft {
        StrategyDraft(editing: strategy.id, name: strategy.name, options: strategy.options)
    }
}

/// A deleted custom strategy and where it was, so Undo can put it back.
struct DeletedStrategy: Equatable {
    let strategy: CustomStrategy
    let index: Int
    let wasActive: Bool
}

extension AppModel {
    /// The strategy in use, built-in or custom.
    var selection: StrategySelection {
        get { StrategySelection(storedID: presetID) }
        set { choose(newValue) }
    }

    /// The chosen strategy's name and flags. Falls back to the default preset
    /// when the chosen custom one was deleted.
    var activeStrategy: ResolvedStrategy { ResolvedStrategy(selection, custom: customStrategies) }

    /// Uses a strategy; a running tunnel restarts with it.
    func choose(_ selection: StrategySelection) {
        guard presetID != selection.storedID else { return }
        presetID = selection.storedID
    }

    /// Saves the editor's strategy and selects it. Editing keeps the same one.
    @discardableResult
    func save(_ draft: StrategyDraft) -> CustomStrategy {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategy: CustomStrategy
        if let id = draft.editing, let i = customStrategies.firstIndex(where: { $0.id == id }) {
            customStrategies[i].name = name
            customStrategies[i].commandLine = draft.options.commandLine
            strategy = customStrategies[i]
        } else {
            strategy = CustomStrategy(name: name, commandLine: draft.options.commandLine)
            customStrategies.append(strategy)
        }
        if selection == strategy.selection { restartIfRunning() } else { choose(strategy.selection) }
        return strategy
    }

    /// Deletes a custom strategy. Deleting the one in use falls back to the default preset.
    @discardableResult
    func delete(_ strategy: CustomStrategy) -> DeletedStrategy? {
        guard let index = customStrategies.firstIndex(where: { $0.id == strategy.id }) else { return nil }
        let wasActive = selection == strategy.selection
        customStrategies.remove(at: index)
        if wasActive { choose(.default) }
        return DeletedStrategy(strategy: strategy, index: index, wasActive: wasActive)
    }

    /// Undoes a delete: the strategy comes back in its place, in use again if it was.
    func restore(_ deleted: DeletedStrategy) {
        guard !customStrategies.contains(where: { $0.id == deleted.strategy.id }) else { return }
        customStrategies.insert(deleted.strategy, at: min(deleted.index, customStrategies.count))
        if deleted.wasActive { choose(deleted.strategy.selection) }
    }

    // MARK: - Flags as text (S-031)

    func copyFlags(_ commandLine: String) {
        UIPasteboard.general.string = commandLine
    }

    /// tpws flags in pasted text, or nil when it is something else. The editor
    /// reads the clipboard through a PasteButton, so iOS does not ask each time.
    func flags(fromPasted text: String) -> StrategyOptions? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("--"), text.count < 2000 else { return nil }
        return StrategyOptions(commandLine: text)
    }
}
