import SwiftUI

/// Every strategy as a card, like ZapretMac's Strategies page: the built-in
/// ones, then "Yours". Tap one to use it; touch and hold for more.
struct StrategiesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var draft: StrategyDraft?
    @State private var deleted: DeletedStrategy?

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: Space.lg, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                section("Built-in", caption: "Ready-made strategies from zapret. Start with the first one; if a site still does not open, try the next.") {
                    ForEach(Preset.all) { preset in
                        let selection = StrategySelection.preset(preset.id)
                        StrategyCard(name: preset.name, symbol: preset.symbol, blurb: preset.blurb,
                                     commandLine: preset.commandLine, inUse: model.selection == selection) {
                            model.choose(selection)
                        }
                        .contextMenu {
                            Button("Use", systemImage: "checkmark.circle") { model.choose(selection) }
                            Button("Copy Flags", systemImage: "doc.on.doc") { model.copyFlags(preset.commandLine) }
                            Button("Duplicate and Edit", systemImage: "plus.square.on.square") {
                                draft = .new(from: preset.options, name: String(localized: "\(preset.name) Copy"))
                            }
                        }
                    }
                }
                section("Yours", caption: "Strategies you made from tpws options.") {
                    ForEach(model.customStrategies) { strategy in
                        StrategyCard(name: strategy.name, symbol: "person.crop.circle",
                                     blurb: strategy.options.summary, commandLine: strategy.commandLine,
                                     inUse: model.selection == strategy.selection) {
                            model.choose(strategy.selection)
                        }
                        .contextMenu {
                            Button("Use", systemImage: "checkmark.circle") { model.choose(strategy.selection) }
                            Button("Edit", systemImage: "pencil") { draft = .edit(strategy) }
                            Button("Copy Flags", systemImage: "doc.on.doc") { model.copyFlags(strategy.commandLine) }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                draft = .new(from: strategy.options, name: String(localized: "\(strategy.name) Copy"))
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(strategy) }
                        }
                    }
                    NewStrategyCard { draft = .new() }
                }
            }
            .padding(Space.margin)
            .padding(.bottom, deleted == nil ? 0 : 72)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Strategies")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Strategy", systemImage: "plus") { draft = .new() }
            }
        }
        .sheet(item: $draft) { draft in
            StrategyEditor(draft: draft)
        }
        .overlay(alignment: .bottom) {
            if let deleted {
                UndoToast(name: deleted.strategy.name) { undo(deleted) }
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, Space.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: deleted)
        .task(id: deleted) {
            // The toast goes away by itself; shake to undo still works after.
            guard deleted != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { deleted = nil }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, caption: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.title3.weight(.semibold))
                Text(caption).font(.callout).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: Space.lg) {
                content()
            }
        }
    }

    /// Deletes and offers Undo, both in a toast and through shake to undo.
    private func delete(_ strategy: CustomStrategy) {
        guard let removed = model.delete(strategy) else { return }
        deleted = removed
        undoManager?.registerUndo(withTarget: model) { model in
            MainActor.assumeIsolated { model.restore(removed) }
        }
        undoManager?.setActionName(String(localized: "Delete Strategy"))
    }

    private func undo(_ removed: DeletedStrategy) {
        undoManager?.removeAllActions(withTarget: model)
        model.restore(removed)
        deleted = nil
    }
}

private struct StrategyCard: View {
    let name: String
    let symbol: String
    let blurb: String
    let commandLine: String
    let inUse: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
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
                    Text(name).font(.headline).foregroundStyle(.primary)
                    Text(blurb)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(commandLine.isEmpty ? String(localized: "no flags") : commandLine)
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
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: inUse)
        .accessibilityAddTraits(inUse ? .isSelected : [])
    }
}

/// The dashed card at the end of "Yours".
private struct NewStrategyCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.sm) {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Palette.accentText)
                Text("New Strategy").font(.headline).foregroundStyle(.primary)
                Text("Pick tpws options in a form")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 2, dash: [8, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// "Deleted “Name”" with an Undo button, at the bottom of the page.
private struct UndoToast: View {
    let name: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text("Deleted “\(name)”")
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: Space.sm)
            Button("Undo", action: undo)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.accentText)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .glassEffect(.regular, in: Capsule())
    }
}
