import SwiftUI

/// The sheet for making or changing a strategy, with every common tpws
/// option as a control and a live preview of the flags, like ZapretMac's.
///
/// ZapretMac checks the flags with `tpws --dry-run`. iOS cannot run tpws in
/// the app (it lives in the tunnel extension and runs once per process), so
/// StrategyCheck applies tpws's parsing rules in Swift instead, live, and
/// Create stays off until the flags pass.
struct StrategyEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StrategyDraft
    @State private var extraText: String
    @State private var pasteFailed = false

    init(draft: StrategyDraft) {
        _draft = State(initialValue: draft)
        _extraText = State(initialValue: draft.options.extra.joined(separator: " "))
    }

    private var options: StrategyOptions {
        var o = draft.options
        o.extra = CommandLineWords.split(extraText)
        return o
    }

    private var issues: [StrategyCheck.Issue] { StrategyCheck.issues(options.arguments) }
    private var oobWithDisorder: Bool { draft.options.oob && draft.options.disorder }
    private var nameIsEmpty: Bool { draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("My Provider"))
                }
                splitting
                httpTricks
                advanced
                command
            }
            .navigationTitle(draft.editing == nil ? "New Strategy" : "Edit Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.editing == nil ? "Create" : "Save", role: .confirm) { save() }
                        .disabled(nameIsEmpty || !issues.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(draft.editing == nil ? !nameIsEmpty : false)
    }

    // MARK: - Sections

    private var splitting: some View {
        Section {
            FlagField("Split at", text: $draft.options.splitPositions, prompt: "1,midsld")
            FlagField("TLS record split", text: $draft.options.tlsRecord, prompt: "sniext+1")
            Toggle("Send pieces out of order (disorder)", isOn: $draft.options.disorder)
            Toggle("Add an out-of-band byte (oob)", isOn: $draft.options.oob)
            if oobWithDisorder {
                WarningNote("On iPhone, an out-of-band byte and disorder together break connections. Turn on only one of them.")
            }
            Toggle("Split every protocol, not only HTTP and TLS", isOn: $draft.options.splitAnyProtocol)
        } header: {
            Text("Splitting")
        } footer: {
            Text("Where to cut the first packet. A number is a byte offset; markers: method, host, endhost, sld (the site name), midsld (its middle), endsld, sniext (the TLS server-name field). Add +N or -N.")
        }
    }

    private var httpTricks: some View {
        Section {
            Toggle("host: lowercase", isOn: $draft.options.hostCase)
            Toggle("MiXeD domain case", isOn: $draft.options.domainCase)
            Toggle("Dot after host", isOn: $draft.options.hostDot)
            Toggle("Tab after host", isOn: $draft.options.hostTab)
            Toggle("No space after Host:", isOn: $draft.options.hostNoSpace)
            Toggle("Line break before method", isOn: $draft.options.methodEOL)
            Toggle("Extra space after method", isOn: $draft.options.methodSpace)
            Toggle("Unix line endings", isOn: $draft.options.unixEOL)
            FlagField("Host spelling", text: $draft.options.hostSpell, prompt: "hoSt")
            FlagField("Padding before Host", text: $draft.options.hostPad, prompt: "1024", keyboard: .numberPad)
        } header: {
            Text("HTTP header tricks")
        } footer: {
            Text("For sites that still use plain HTTP. Host spelling is exactly 4 letters; padding adds that many bytes of dummy headers before Host, so the filter gives up before it reaches the site name.")
        }
    }

    private var advanced: some View {
        Section {
            FlagField("Only these ports", text: $draft.options.tcpPorts, prompt: "80,443")
            LabeledContent("Only these protocols") {
                HStack(spacing: Space.xs) {
                    Toggle("HTTP", isOn: protocolBinding(.http))
                    Toggle("TLS", isOn: protocolBinding(.tls))
                    Toggle("Other", isOn: protocolBinding(.unknown))
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Picker("Disorder applies to", selection: $draft.options.disorderScope) { scopeOptions }
                .disabled(!draft.options.disorder)
            Picker("Out-of-band byte applies to", selection: $draft.options.oobScope) { scopeOptions }
                .disabled(!draft.options.oob)
            FlagField("Out-of-band byte value", text: $draft.options.oobData, prompt: "0x00")
                .disabled(!draft.options.oob)
            FlagField("Start changing at", text: $draft.options.tamperStart, prompt: "0")
            FlagField("Stop changing after", text: $draft.options.tamperCutoff, prompt: "n2")
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("More tpws flags")
                TextField("More tpws flags", text: $extraText,
                          prompt: Text(verbatim: "--hostlist-domains=example.com"), axis: .vertical)
                    .font(.callout.monospaced())
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if options.hasSecondProfile {
                Label("This strategy has a separate part for HTTP and HTTPS; it is kept in More tpws flags.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("No protocol picked means every protocol; Other is anything that is not HTTP or TLS. Start and stop take a byte offset, or n and a data block, like n2. The out-of-band byte is one character or 0x and two hex digits. Any tpws desync flag works under More tpws flags.")
        }
    }

    private var command: some View {
        Section {
            Text(options.commandLine.isEmpty ? String(localized: "No flags: traffic is passed through unchanged.") : options.commandLine)
                .font(.callout.monospaced())
                .foregroundStyle(options.commandLine.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if issues.isEmpty {
                Label("tpws accepts these flags.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(issues) { issue in
                    Label(issue.message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first, let pasted = model.flags(fromPasted: text) else {
                    pasteFailed = true
                    return
                }
                draft.options = pasted
                extraText = pasted.extra.joined(separator: " ")
                pasteFailed = false
            }
            .labelStyle(.titleAndIcon)
            if pasteFailed {
                Text("The clipboard does not hold tpws flags. Copy flags that start with --.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Command")
        } footer: {
            Text("Checked on this iPhone against tpws's rules. Paste replaces the options with tpws flags from the clipboard.")
        }
    }

    @ViewBuilder private var scopeOptions: some View {
        Text("Every protocol").tag(ProtocolScope.all)
        Text("HTTP only").tag(ProtocolScope.http)
        Text("TLS only").tag(ProtocolScope.tls)
    }

    private func protocolBinding(_ proto: L7Protocol) -> Binding<Bool> {
        Binding(get: { draft.options.filters(proto) },
                set: { draft.options.setFilter(proto, $0) })
    }

    private func save() {
        var final = draft
        final.options = options
        model.save(final)
        dismiss()
    }
}

/// A labeled text field for one tpws value: label on the left, the value on
/// the right in monospaced type, never autocorrected.
private struct FlagField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let prompt: String
    var keyboard: UIKeyboardType = .asciiCapable

    init(_ title: LocalizedStringKey, text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .asciiCapable) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.keyboard = keyboard
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(verbatim: prompt))
                .labelsHidden()
                .font(.body.monospaced())
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

/// An orange note under a control whose setting does not work on iPhone.
private struct WarningNote: View {
    let message: LocalizedStringKey

    init(_ message: LocalizedStringKey) { self.message = message }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
    }
}
