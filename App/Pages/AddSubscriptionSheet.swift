import SwiftUI

/// Takes the address of a site list, downloads it, and adds it under Sites.
/// Below the form, known community lists fill it in with one tap, as on the Mac.
struct AddSubscriptionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var name = ""
    @State private var excluded: Bool
    @State private var kind: ListKind = .domains
    @State private var downloading = false
    @State private var error: String?
    @FocusState private var addressFocused: Bool

    init(excluded: Bool) {
        _excluded = State(initialValue: excluded)
    }

    private var url: URL? { SiteListSubscription.url(from: address) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $address, prompt: Text(verbatim: "https://example.com/list.txt"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .submitLabel(.go)
                        .focused($addressFocused)
                        .onSubmit(add)
                    TextField("Name", text: $name,
                              prompt: Text(url.map(SiteListSubscription.defaultName) ?? String(localized: "From the address")))
                    Picker("Kind", selection: $kind) {
                        Text("Sites").tag(ListKind.domains)
                        Text("IP Addresses").tag(ListKind.addresses)
                    }
                    Picker("Add to", selection: $excluded) {
                        Text("Sites to Unblock").tag(false)
                        Text("Never Touch").tag(true)
                    }
                } footer: {
                    if kind == .domains {
                        Text("A text file with one domain per line, like zapret's lists. Lines starting with # are skipped, and gzip files work. Zapret downloads it again every day.")
                    } else {
                        Text("A text file with one IP address or range per line, like 203.0.113.0/24 or 2001:db8::/32. Lines starting with # are skipped, and gzip files work. Zapret downloads it again every day.")
                    }
                }
                if !address.isEmpty && url == nil {
                    Label("Enter an address that starts with https://", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Section {
                    ForEach(SuggestedLists.all) { list in
                        SuggestionRow(list: list, isChosen: url == list.url) { choose(list) }
                    }
                } header: {
                    Text("Suggested Lists")
                } footer: {
                    Text("Lists that zapret's own scripts download. Choose one to fill in the form.")
                }
            }
            .navigationTitle("Add Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if downloading {
                        ProgressView()
                    } else {
                        Button("Subscribe", action: add)
                            .disabled(url == nil)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if downloading {
                    Label("Downloading…", systemImage: "arrow.down.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Space.sm)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
            .onChange(of: address) { error = nil }
            .onChange(of: kind) { error = nil }
            .interactiveDismissDisabled(downloading)
        }
    }

    /// Fills the form with a suggested list; Subscribe still downloads it.
    private func choose(_ list: SuggestedList) {
        address = list.url.absoluteString
        name = list.name
        kind = list.kind
        excluded = false
        error = nil
        addressFocused = false
    }

    private func add() {
        guard let url, !downloading else { return }
        downloading = true
        error = nil
        Task {
            let failure = await model.lists.add(url: url, name: name, excluded: excluded, kind: kind)
            downloading = false
            if let failure { error = failure } else { dismiss() }
        }
    }
}

/// One suggested list: what it holds, and the country it is for. Tapping
/// the row fills the form; the arrow opens the list's page.
private struct SuggestionRow: View {
    let list: SuggestedList
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            Button(action: choose) {
                HStack(spacing: Space.md) {
                    Image(systemName: list.kind == .domains ? "globe" : "number")
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.xs) {
                            Text(verbatim: list.name)
                                .foregroundStyle(.primary)
                            if let country = list.countryName {
                                Text(country)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(list.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: Space.sm)
                    if isChosen {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.accentText)
                            .accessibilityLabel(Text("Chosen"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(list.kind == .domains ? Text("A list of sites") : Text("A list of IP addresses"))
            Link(destination: list.source) {
                Label("Open the List's Page", systemImage: "arrow.up.right.square")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Palette.accentText)
            }
            .buttonStyle(.borderless)
        }
    }
}
