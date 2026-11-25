import SwiftUI

/// The Overview strategy menu's choices: the built-in strategies, then the
/// person's own, like ZapretMac's "Built-in" and "Yours".
struct StrategyPicker: View {
    @Binding var selection: StrategySelection
    let custom: [CustomStrategy]

    var body: some View {
        Picker("Strategy", selection: $selection) {
            Section("Built-in") {
                ForEach(Preset.all) { preset in
                    Label(preset.name, systemImage: preset.symbol).tag(StrategySelection.preset(preset.id))
                }
            }
            if !custom.isEmpty {
                Section("Yours") {
                    ForEach(custom) { strategy in
                        Label(strategy.name, systemImage: "person.crop.circle").tag(strategy.selection)
                    }
                }
            }
        }
    }
}
