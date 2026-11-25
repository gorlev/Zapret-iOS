import SwiftUI
import UniformTypeIdentifiers

/// My list and Never Touch, with subscriptions, IP ranges, and the
/// automatic list, like ZapretMac's Sites page.
struct SitesPage: View {
    @Environment(AppModel.self) private var model
    @State private var list: Which = .unblock
    @State private var draft = ""
    @State private var note: String?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var addingSubscription = false
    @State private var importing = false
    @FocusState private var fieldFocused: Bool

    enum Which: Hashable { case unblock, never }

    private var excluded: Bool { list == .never }
    private var entries: [SiteEntry] { excluded ? model.excludeSites : model.includeSites }
    /// My list splits into sites and, under them, IP addresses.
    private var siteEntries: [SiteEntry] { entries.filter { !$0.isAddress } }
    private var addressEntries: [SiteEntry] { entries.filter(\.isAddress) }
    private var subscriptions: [ListSubscription] { model.lists.subscriptions(excluded: excluded) }

    var body: some View {
        List(selection: $selection) {
            addSection
            if !subscriptions.isEmpty { subscriptionsSection }
            if !excluded { autoSection }
            Section {
                if siteEntries.isEmpty && addressEntries.isEmpty && subscriptions.isEmpty {
                    emptyState
                } else if siteEntries.isEmpty {
                    Text("No sites. Type one above.")
                        .foregroundStyle(.secondary)
                } else {
                    rows(siteEntries)
                }
            } header: {
                Text(excluded ? "Never Touch" : "My List")
            }
            if !addressEntries.isEmpty {
                Section {
                    rows(addressEntries)
                } header: {
                    Text("IP Addresses")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Sites")
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { undoBar }
        .animation(.default, value: model.lists.undo?.id)
        .sheet(isPresented: $addingSubscription) {
            AddSubscriptionSheet(excluded: excluded)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let added = model.importSites(from: urls, excluded: excluded)
            note = String(localized: "Added \(added) sites.")
        }
        .onChange(of: list) { selection = []; editMode = .inactive; note = nil }
        // tpws appends to the automatic list while the bypass runs: look at the
        // file every two seconds while the page is open.
        .task {
            while !Task.isCancelled {
                model.lists.reloadAutoSites()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Sections

    private var addSection: some View {
        Section {
            HStack(spacing: Space.sm) {
                TextField(excluded ? "Add a site or IP range never to touch" : "Add sites or IP addresses",
                          text: $draft,
                          prompt: Text(excluded ? "mybank.com" : "youtube.com 203.0.113.0/24"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(isEmpty(IPRanges.route(draft)))
            }
        } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let note {
                    Text(note).foregroundStyle(Palette.accentText)
                } else {
                    Text(footer)
                }
                if !excluded && model.scope == .allSites {
                    Button("Use My List") { model.scope = .listOnly }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
                HStack(spacing: Space.sm) {
                    Text("\(siteEntries.count) sites")
                    if !addressEntries.isEmpty { Text("\(addressEntries.count) IP addresses") }
                }
                .monospacedDigit()
            }
        }
    }

    private var subscriptionsSection: some View {
        Section {
            ForEach(subscriptions) { subscription in
                SubscriptionRow(subscription: subscription)
                    .tag(subscription.id)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.lists.remove([subscription.uuid])
                        }
                        Button("Update Now", systemImage: "arrow.clockwise") {
                            Task { await model.lists.update(subscription.uuid) }
                        }
                        .tint(Palette.accent)
                    }
                    .contextMenu { subscriptionMenu(subscription) }
            }
        } header: {
            Text("Subscriptions")
        } footer: {
            if model.lists.enabledEntryCount > SiteLists.comfortableEntries {
                Label("These lists hold \(model.lists.enabledEntryCount) entries. The VPN on iPhone has little memory, so very large lists can keep it from starting. Turn off the ones you do not need.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private func subscriptionMenu(_ subscription: ListSubscription) -> some View {
        Button("Update Now", systemImage: "arrow.clockwise") { Task { await model.lists.update(subscription.uuid) } }
            .disabled(model.lists.updating.contains(subscription.uuid))
        Button(subscription.isEnabled ? "Turn Off" : "Turn On",
               systemImage: subscription.isEnabled ? "pause.circle" : "checkmark.circle") {
            model.setSubscriptionEnabled(subscription, !subscription.isEnabled)
        }
        Button("Copy Address", systemImage: "doc.on.doc") { UIPasteboard.general.string = subscription.url }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { model.lists.remove([subscription.uuid]) }
    }

    /// The option for tpws to add failing sites by itself, and what it added.
    private var autoSection: some View {
        Section {
            Toggle("Add blocked sites automatically",
                   isOn: Binding(get: { model.lists.autoHostlist }, set: { model.setAutoHostlist($0) }))
            if model.lists.autoHostlist || !model.lists.autoSites.isEmpty {
                if model.lists.autoSites.isEmpty {
                    Text("Nothing yet. A site appears here when its connections keep failing.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.lists.autoSites, id: \.self) { site in
                        AutoSiteRow(site: site)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteAutoSites([site]) }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Move to My List", systemImage: "plus.circle") {
                                    model.moveAutoSites([site], excluded: false)
                                }
                                .tint(Palette.accent)
                            }
                    }
                }
            }
        } header: {
            HStack(spacing: Space.sm) {
                Text("Added Automatically")
                Spacer()
                if !model.lists.autoSites.isEmpty {
                    Text("\(model.lists.autoSites.count) sites").monospacedDigit()
                    Button("Clear All") { model.clearAutoSites() }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        } footer: {
            Text(autoNote)
        }
    }

    private var autoNote: String {
        if model.scope == .allSites {
            return String(localized: "Works with My list. All sites already changes every site, so there is nothing to add.")
        }
        return String(localized: "tpws adds a site after \(TunnelLists.autoFailThreshold) failed connections within a minute.")
    }

    @ViewBuilder private func rows(_ entries: [SiteEntry]) -> some View {
        ForEach(entries) { entry in
            SiteRow(entry: entry, editing: editMode.isEditing) { model.toggleSite(entry) }
                .tag(entry.id)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSites([entry.id]) }
                }
                .swipeActions(edge: .leading) {
                    Button(excluded ? "Move to Sites to Unblock" : "Move to Never Touch",
                           systemImage: excluded ? "globe" : "hand.raised") {
                        model.moveSites([entry.id], excluded: !excluded)
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    Button(entry.isEnabled ? "Turn Off" : "Turn On",
                           systemImage: entry.isEnabled ? "pause.circle" : "checkmark.circle") { model.toggleSite(entry) }
                    Button(excluded ? "Move to Sites to Unblock" : "Move to Never Touch",
                           systemImage: excluded ? "globe" : "hand.raised") {
                        model.moveSites([entry.id], excluded: !excluded)
                    }
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.domain }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSites([entry.id]) }
                }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(excluded ? "Nothing Excluded" : "No Sites Yet", systemImage: excluded ? "hand.raised" : "globe")
        } description: {
            Text(excluded
                 ? "Sites here are never changed, even with All sites on. Add banks or sites the strategy breaks."
                 : "Add the sites that do not open, like youtube.com or discord.com. Paste many at once.")
        } actions: {
            Button("Add Subscription…") { addingSubscription = true }
        }
    }

    // MARK: - Toolbar and undo

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
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
                    Button("Add Subscription…", systemImage: "link.badge.plus") { addingSubscription = true }
                    Button("Import from File…", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Paste Sites", systemImage: "doc.on.clipboard") { pasteSites() }
                    Divider()
                    Button("Update Subscriptions", systemImage: "arrow.clockwise") { model.lists.updateAll() }
                        .disabled(model.lists.subscriptions.isEmpty)
                    Button("Select", systemImage: "checkmark.circle") { editMode = .active }
                        .disabled(entries.isEmpty && subscriptions.isEmpty)
                }
            }
        }
        if editMode.isEditing {
            ToolbarItem(placement: .bottomBar) {
                Button("Delete \(selection.count)", systemImage: "trash", role: .destructive, action: deleteSelection)
                    .disabled(selection.isEmpty)
            }
        }
    }

    @ViewBuilder private var undoBar: some View {
        if let undo = model.lists.undo {
            HStack(spacing: Space.md) {
                Text(undo.title)
                    .lineLimit(1)
                Spacer(minLength: Space.sm)
                Button("Undo") {
                    model.lists.undo = nil
                    undo.restore()
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.id) {
                try? await Task.sleep(for: .seconds(6))
                if model.lists.undo?.id == undo.id { model.lists.undo = nil }
            }
        }
    }

    // MARK: - Actions

    private var footer: String {
        if excluded { return String(localized: "Sites here always go straight through, whatever the strategy.") }
        return model.scope == .listOnly
            ? String(localized: "Only these sites go through the bypass. Subdomains are included.")
            : String(localized: "The bypass is on for all sites now. This list is used when Sites is set to My list.")
    }

    private func add() {
        if isEmpty(IPRanges.route(draft)) {
            if !draft.isEmpty { note = String(localized: "That does not look like a site or IP address.") }
            return
        }
        let count = model.addSites(draft, excluded: excluded)
        note = count == 0 ? String(localized: "Already in the list.") : String(localized: "Added \(count) sites.")
        draft = ""
    }

    private func pasteSites() {
        guard let text = UIPasteboard.general.string else { return }
        let count = model.addSites(text, excluded: excluded)
        note = String(localized: "Added \(count) sites.")
    }

    private func deleteSelection() {
        let subs = Set(subscriptions.filter { selection.contains($0.id) }.map(\.uuid))
        let sites = selection.filter { !$0.hasPrefix("s:") }
        if !subs.isEmpty { model.lists.remove(subs) }
        if !sites.isEmpty { model.deleteSites(sites) }
        selection = []
        editMode = .inactive
    }

    private func isEmpty(_ routed: (domains: [String], addresses: [String])) -> Bool {
        routed.domains.isEmpty && routed.addresses.isEmpty
    }
}
