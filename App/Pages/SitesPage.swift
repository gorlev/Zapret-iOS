import SwiftUI

/// My list and Never Touch, like ZapretMac's Sites page.
struct SitesPage: View {
    @Environment(AppModel.self) private var model
    @State private var list: Which = .unblock
    @State private var draft = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @FocusState private var fieldFocused: Bool

    enum Which: Hashable { case unblock, never }

    private var entries: [SiteEntry] { list == .unblock ? model.includeSites : model.excludeSites }

    var body: some View {
        List(selection: $selection) {
            Section {
                HStack(spacing: Space.sm) {
                    TextField(list == .unblock ? "Add sites, like youtube.com" : "Add sites never to touch, like mybank.com",
                              text: $draft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($fieldFocused)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(Domains.parseList(draft).isEmpty)
                }
            } footer: {
                Text(footer)
            }

            Section {
                if entries.isEmpty {
                    ContentUnavailableView(list == .unblock ? "No sites yet" : "Nothing excluded",
                                           systemImage: list == .unblock ? "globe" : "hand.raised",
                                           description: Text(list == .unblock
                                               ? "Add the sites that do not open. Subdomains are included."
                                               : "Sites here never go through the bypass, like banks or sites a strategy breaks."))
                } else {
                    ForEach(entries) { entry in
                        SiteRow(entry: entry, editing: editMode.isEditing) { model.toggleSite(entry) }
                            .tag(entry.id)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { model.removeSites([entry.id]) }
                            }
                    }
                }
            } header: {
                HStack {
                    Text(list == .unblock ? "My List" : "Never Touch")
                    Spacer()
                    Text("\(entries.count) sites").monospacedDigit()
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Sites")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("List", selection: $list) {
                    Text("Sites to Unblock").tag(Which.unblock)
                    Text("Never Touch").tag(Which.never)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button("Done") { editMode = .inactive; selection = [] }
                } else {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Select", systemImage: "checkmark.circle") { editMode = .active }
                            .disabled(entries.isEmpty)
                        Button("Paste Sites", systemImage: "doc.on.clipboard") { pasteSites() }
                    }
                }
            }
            if editMode.isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button("Delete \(selection.count)", systemImage: "trash", role: .destructive) {
                        model.removeSites(selection)
                        selection = []
                        editMode = .inactive
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .onChange(of: list) { selection = []; editMode = .inactive }
    }

    private var footer: String {
        if list == .never { return String(localized: "These sites never go through the bypass, even with All sites.") }
        return model.scope == .listOnly
            ? String(localized: "Only these sites go through the bypass. Subdomains are included.")
            : String(localized: "The bypass is set to All sites, so this list is not used now. Choose My list on Overview to use it.")
    }

    private func add() {
        model.addSites(draft, excluded: list == .never)
        draft = ""
    }

    private func pasteSites() {
        guard let text = UIPasteboard.general.string else { return }
        model.addSites(text, excluded: list == .never)
    }
}

private struct SiteRow: View {
    let entry: SiteEntry
    let editing: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            if !editing {
                Button(action: toggle) {
                    Image(systemName: entry.isEnabled ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(entry.isEnabled ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.isEnabled ? "Turn off" : "Turn on")
            }
            Image(systemName: entry.isExcluded ? "hand.raised" : "globe")
                .foregroundStyle(entry.isEnabled ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.tertiary))
            Text(entry.domain)
                .foregroundStyle(entry.isEnabled ? .primary : .secondary)
        }
    }
}
