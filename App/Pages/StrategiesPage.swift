import SwiftUI

/// The built-in strategies as cards, like ZapretMac's Strategies page.
struct StrategiesPage: View {
    @Environment(AppModel.self) private var model
    @State private var showFinder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Built-in").font(.title3.weight(.semibold))
                    Text("Ready-made strategies from zapret. Start with the first one; if a site still does not open, try the next.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Space.lg)], spacing: Space.lg) {
                    ForEach(Preset.all) { preset in
                        StrategyCard(preset: preset, inUse: preset.id == model.presetID) {
                            model.presetID = preset.id
                        }
                    }
                }
            }
            .padding(Space.margin)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Strategies")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Find a Strategy", systemImage: "wand.and.sparkles") { showFinder = true }
            }
        }
        .sheet(isPresented: $showFinder) { FinderSheet() }
    }
}

private struct StrategyCard: View {
    let preset: Preset
    let inUse: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top) {
                    Image(systemName: preset.symbol)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(inUse ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(Palette.accentText))
                        .frame(width: 48, height: 48)
                        .background(inUse ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.accent.opacity(0.12)),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                    if inUse {
                        Label("In use", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accentText)
                    }
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(preset.name).font(.headline).foregroundStyle(.primary)
                    Text(preset.blurb)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(preset.commandLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xs + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .multilineTextAlignment(.leading)
            .padding(Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.accent, lineWidth: inUse ? 2 : 0))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: inUse)
        .accessibilityAddTraits(inUse ? .isSelected : [])
    }
}
