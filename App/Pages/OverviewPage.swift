import SwiftUI

/// The home page: one big switch, what it is doing, the setup, and a site check.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                Hero()
                StatsRow()
                DebugTamperCard() // TEMPORARY
                SetupCard()
                CheckCard()
                if !model.hostsSeen.isEmpty { RecentSitesCard() }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.isOn ? String(localized: "Turn Off") : String(localized: "Turn On"),
                       systemImage: model.isOn ? "stop.fill" : "play.fill") { model.toggle() }
            }
        }
    }
}

// MARK: - Hero

private struct Hero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Space.lg) {
            PowerButton(state: model.state) { model.toggle() }
                .padding(.vertical, Space.lg)
            VStack(spacing: Space.xs) {
                Text(headline)
                    .font(.title.weight(.semibold))
                Text(subline)
                    .font(.callout)
                    .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var failed: Bool { if case .failed = model.state { true } else { false } }

    private var headline: String {
        switch model.state {
        case .stopped: String(localized: "Bypass is off")
        case .starting: String(localized: "Starting…")
        case .stopping: String(localized: "Stopping…")
        case .running: String(localized: "Bypass is on")
        case .failed: String(localized: "The bypass stopped")
        }
    }

    private var subline: String {
        switch model.state {
        case .stopped: String(localized: "Tap the button. Every app's traffic then goes through tpws on this iPhone, as a local VPN.")
        case .starting, .stopping: String(localized: "Setting up the local VPN and tpws.")
        case .running: String(localized: "Every app goes through tpws with \(model.preset.name). Nothing leaves this iPhone through a server.")
        case .failed(let message): message
        }
    }
}

/// The round switch, the same as ZapretMac's.
struct PowerButton: View {
    let state: AppModel.State
    var size: CGFloat = 148
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat { size / 148 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(isOn ? 0.18 : 0))
                    .frame(width: size + 48 * scale, height: size + 48 * scale)
                    .blur(radius: 12 * scale)
                Circle()
                    .strokeBorder(isOn ? AnyShapeStyle(Palette.accent.opacity(0.35)) : AnyShapeStyle(.quaternary),
                                  lineWidth: 8 * scale)
                    .frame(width: size + 24 * scale, height: size + 24 * scale)
                Circle()
                    .fill(fill)
                    .frame(width: size, height: size)
                    .shadow(color: isOn ? Palette.accent.opacity(0.45) : .black.opacity(0.12),
                            radius: (isOn ? 20 : 8) * scale, y: (isOn ? 8 : 4) * scale)
                    .overlay(Circle().strokeBorder(.white.opacity(isOn ? 0.25 : 0.08), lineWidth: 1))
                if state == .starting || state == .stopping {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Palette.onAccent)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 52 * scale, weight: .semibold))
                        .foregroundStyle(isOn ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: state)
        .accessibilityLabel(isOn ? String(localized: "Turn bypass off") : String(localized: "Turn bypass on"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var isOn: Bool { state == .running || state == .starting }

    private var fill: AnyShapeStyle {
        isOn ? AnyShapeStyle(Palette.heroFill) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

/// Shrinks a little while pressed, in place of the Mac's hover.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Stats

private struct StatsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.md) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatTile(title: "Running for", symbol: "clock",
                         value: model.startedAt.map { Uptime.format(context.date.timeIntervalSince($0)) } ?? "—")
            }
            StatTile(title: "Connections", symbol: "arrow.left.arrow.right",
                     value: model.isOn ? model.connections.formatted() : "—")
            StatTile(title: "Sites seen", symbol: "globe",
                     value: model.isOn ? model.hostsSeen.count.formatted() : "—")
        }
    }
}

private struct StatTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Setup

private struct SetupCard: View {
    @Environment(AppModel.self) private var model

    private var includeCount: Int { model.includeSites.filter(\.isEnabled).count }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            CardRow(title: "Strategy", symbol: "slider.horizontal.3",
                    caption: String(localized: "How tpws changes your traffic so the filter cannot read it.")) {
                Menu {
                    Picker("Strategy", selection: $model.presetID) {
                        ForEach(Preset.all) { preset in
                            Label(preset.name, systemImage: preset.symbol).tag(preset.id)
                        }
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(model.preset.name).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.accentText)
                }
            }
            Divider().padding(.leading, 52)
            CardRow(title: "Sites", symbol: "globe",
                    caption: model.scope == .listOnly && includeCount == 0
                        ? String(localized: "Your list is empty. Add sites on the Sites page, or choose All sites.")
                        : (model.scope == .allSites ? String(localized: "Every site goes through the bypass.")
                                                    : String(localized: "Only the \(includeCount) sites in your list."))) {
                Picker("Sites", selection: $model.scope) {
                    Text("All sites").tag(Scope.allSites)
                    Text("My list").tag(Scope.listOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Divider().padding(.leading, 52)
            CardRow(title: "Encrypted DNS", symbol: "lock.shield",
                    caption: String(localized: "Looks up site names over HTTPS, so DNS blocks do not apply.")) {
                Picker("Encrypted DNS", selection: $model.dns) {
                    Text("Cloudflare").tag(DNSChoice.cloudflare)
                    Text("Google").tag(DNSChoice.google)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .card()
    }
}

private struct CardRow<Control: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let caption: String
    @ViewBuilder var control: Control

    var body: some View {
        // On a phone the caption gets the full width under the title and control.
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Space.md) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 24)
                Text(title).font(.body.weight(.medium))
                Spacer(minLength: Space.sm)
                control
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 24 + Space.md)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }
}

// MARK: - Check a site

private struct CheckCard: View {
    @Environment(AppModel.self) private var model
    @State private var address = "https://discord.com"
    @State private var result: SiteCheck.Result?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label("Check a site", systemImage: "checkmark.seal")
                .font(.headline)
            HStack(spacing: Space.sm) {
                TextField("https://example.com", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(check)
                Button("Check", action: check)
                    .buttonStyle(.borderedProminent)
                    .disabled(checking || address.isEmpty)
            }
            if checking {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if let result {
                Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(result.ok ? AnyShapeStyle(.green) : AnyShapeStyle(.red))
            }
            Text(model.isOn ? String(localized: "Opens the address through the bypass.")
                            : String(localized: "The bypass is off: this opens the address directly."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Space.lg)
        .card()
    }

    private func check() {
        checking = true
        result = nil
        Task {
            result = await SiteCheck.run(address)
            checking = false
        }
    }
}

enum SiteCheck {
    struct Result { let ok: Bool; let text: String }

    static func run(_ raw: String) async -> Result {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return Result(ok: false, text: String(localized: "That is not a web address.")) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        let start = Date.now
        do {
            let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            let ms = Int(Date.now.timeIntervalSince(start) * 1000)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Result(ok: true, text: String(localized: "Opened in \(ms) ms (HTTP \(code))."))
        } catch {
            return Result(ok: false, text: error.localizedDescription)
        }
    }
}

// MARK: - Recent sites

private struct RecentSitesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label("Recent sites", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            ForEach(model.hostsSeen.prefix(8), id: \.self) { host in
                HStack {
                    Text(host).font(.callout)
                    Spacer()
                    if !model.includeSites.contains(where: { $0.domain == host }) {
                        Button("Add to My list", systemImage: "plus.circle") { model.addSites(host, excluded: false) }
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
