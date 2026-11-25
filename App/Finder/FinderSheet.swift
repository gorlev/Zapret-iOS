import SwiftUI

/// "Find a Strategy", like ZapretMac's sheet: tries every strategy against one
/// or more sites and shows which ones open all of them, fastest first.
struct FinderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var finder = StrategyFinder()
    @AppStorage("finderSites") private var sitesText = "discord.com"
    @AppStorage("finderDepth") private var depth: ScanDepth = .quick
    @AppStorage("finderRepeats") private var repeats = 1
    /// Scan rows whose flags were handed to the app with Use.
    @State private var adopted: Set<String> = []
    @FocusState private var editing: Bool

    /// Sites to fill in, from the Overview site check.
    var initialSites: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    setupCard
                    if showsStatus { statusCard }
                    if !finder.trials.isEmpty { resultsCard }
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.lg)
                .frame(maxWidth: .infinity)
                .animation(.default, value: finder.ranked.map(\.id))
                .animation(.default, value: finder.phase)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Find a Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        finder.stop()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(finder.isRunning)
        .onAppear {
            if let initialSites, !initialSites.isEmpty { sitesText = initialSites }
            #if DEBUG
            if let sample = FinderSample.current {
                if sample != .start { depth = .thorough }
                finder.loadSample(sample)
            }
            #endif
        }
    }

    // MARK: - Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Zapret turns the bypass on with each strategy in turn and opens the sites through it. When it is done, your strategy and the switch go back to how they were.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.md) {
                    Picker("Scan", selection: $depth) {
                        Text("Quick").tag(ScanDepth.quick)
                        Text("Thorough").tag(ScanDepth.thorough)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if depth == .thorough {
                        Menu {
                            Picker("Repeat each try", selection: $repeats) {
                                Text("Once").tag(1)
                                Text("3 times").tag(3)
                            }
                        } label: {
                            HStack(spacing: Space.xs) {
                                Text(repeats == 1 ? String(localized: "Once") : String(localized: "3 times"))
                                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                            }
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Palette.accentText)
                        }
                        .accessibilityLabel("Repeat each try")
                        .fixedSize()
                    }
                }
                Text(depthHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(finder.isRunning)
            VStack(alignment: .leading, spacing: Space.sm) {
                TextField("Blocked sites", text: $sitesText, prompt: Text(verbatim: "discord.com youtube.com"))
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.go)
                    .onSubmit(start)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($editing)
                    .disabled(finder.isRunning)
                Text("One site, or several separated by spaces. A strategy works only if every site opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if finder.isRunning {
                        Button(role: .cancel) { finder.stop() } label: { Text("Stop").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                            .disabled(finder.phase == .restoring)
                    } else {
                        Button(action: start) {
                            Text(finder.trials.isEmpty ? String(localized: "Start Test") : String(localized: "Test Again"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(FinderProbe.urls(from: sitesText).isEmpty)
                    }
                }
                .controlSize(.large)
            }
        }
        .padding(Space.lg)
        .card()
    }

    private var depthHelp: String {
        switch depth {
        case .quick:
            String(localized: "Tries the \(Preset.all.count) built-in strategies. About a minute.")
        case .thorough:
            String(localized: "Tries every split and TLS-record combination zapret's blockcheck tests, with TLS 1.3 and TLS 1.2 separately. Takes a few minutes.")
        }
    }

    // MARK: - Status

    private var showsStatus: Bool { finder.phase != .idle }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if finder.direct.count == 1, let direct = finder.direct.first {
                HStack(spacing: Space.sm) {
                    Text("Without Zapret")
                    Spacer()
                    OutcomeLabel(outcome: direct.outcome)
                }
                .font(.callout)
            } else if !finder.direct.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Without Zapret").font(.callout)
                    ForEach(finder.direct) { direct in
                        HStack(spacing: Space.sm) {
                            Text(verbatim: direct.site)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            OutcomeLabel(outcome: direct.outcome).lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
            }
            if finder.phase == .diagnosing {
                HStack(spacing: Space.sm) {
                    ProgressView()
                    Text("Finding out what kind of block it is…").foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                ForEach(verdicts, id: \.kind) { verdict in
                    BlockVerdictLine(kind: verdict.kind, sites: finder.sites.count > 1 ? verdict.sites : [])
                }
            }
            if !finder.trials.isEmpty, finder.phase != .diagnosing {
                Divider()
                progressLine
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var progressLine: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                if finder.phase == .restoring {
                    ProgressView()
                } else if finder.phase == .finished {
                    Image(systemName: finder.workingCount > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(finder.workingCount > 0 ? Color.green : Color.red)
                }
                Text(summary)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            if finder.phase == .trying {
                ProgressView(value: Double(finder.finishedCount), total: Double(max(finder.trials.count, 1)))
                    .tint(Palette.accent)
            }
        }
    }

    /// One line per kind of block, worst first, with the sites that have it.
    private var verdicts: [(kind: BlockKind, sites: [String])] {
        BlockKind.allCases.compactMap { kind in
            let sites = finder.diagnoses.filter { $0.kind == kind }.map(\.site)
            return sites.isEmpty ? nil : (kind, sites)
        }
    }

    private var summary: String {
        let done = finder.finishedCount
        let total = finder.trials.count
        switch finder.phase {
        case .idle, .diagnosing: return ""
        case .trying:
            if let n = finder.currentNumber { return String(localized: "Try \(n) of \(total)…") }
            return String(localized: "\(done) of \(total) tried…")
        case .restoring: return String(localized: "Putting your strategy back…")
        case .stopped: return String(localized: "Stopped after \(done) of \(total).")
        case .finished:
            if finder.sites.count > 1 {
                if finder.workingCount == 0 { return String(localized: "No strategy opened every site.") }
                return String(localized: "\(finder.workingCount) strategies open every site.")
            }
            if finder.workingCount == 0 { return String(localized: "No strategy opened \(finder.site).") }
            return String(localized: "\(finder.workingCount) strategies open \(finder.site).")
        }
    }

    // MARK: - Results

    private var resultsCard: some View {
        let rows = finder.ranked
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { offset, trial in
                TrialRow(trial: trial, multipleSites: finder.sites.count > 1) {
                    useButton(for: trial)
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                if offset < rows.count - 1 {
                    Divider().padding(.leading, Space.lg + 24 + Space.md)
                }
            }
        }
        .card()
    }

    @ViewBuilder private func useButton(for trial: Trial) -> some View {
        if trial.arguments == model.activeStrategy.arguments || adopted.contains(trial.id) {
            Text(String(localized: "In use"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.accentText)
        } else {
            Button("Use") {
                model.adoptFoundStrategy(name: trial.name, arguments: trial.arguments)
                adopted.insert(trial.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Palette.accentText)
            .disabled(finder.isRunning)
        }
    }

    private func start() {
        editing = false
        let urls = FinderProbe.urls(from: sitesText)
        guard !urls.isEmpty else { return }
        adopted = []
        finder.start(urls: urls, depth: depth, repeats: repeats, model: model)
    }
}

/// One strategy's result: the name, the flags under it on scan rows, the TLS
/// versions it worked with, and the time and Use on rows that work.
private struct TrialRow<Action: View>: View {
    let trial: Trial
    let multipleSites: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            icon.frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(trial.name)
                    .font(.callout)
                    .foregroundStyle(trial.status == .waiting ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: trial.arguments.joined(separator: " "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !trial.versions.isEmpty { TLSMarks(versions: trial.versions) }
                if trial.worksOnlyWithTLS13 {
                    Text("Works in browsers; some older apps may not get through.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .fails(let reason) = trial.status {
                    Text(trial.isPartial ? String(localized: "Opened \(trial.openCount) of \(trial.sites.count)") : reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Space.sm)
            trailing
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var trailing: some View {
        switch trial.status {
        case .waiting, .fails: EmptyView()
        case .testing:
            Text("Testing…").font(.callout).foregroundStyle(.secondary)
        case .works(let ms):
            VStack(alignment: .trailing, spacing: Space.xs) {
                action()
                Text("\(ms) ms").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .fixedSize()
        }
    }

    @ViewBuilder private var icon: some View {
        switch trial.status {
        case .waiting: Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        case .testing: ProgressView()
        case .works: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .fails: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

/// "TLS 1.3 ✓  TLS 1.2 ✗": which TLS versions a scan try worked with.
private struct TLSMarks: View {
    let versions: [VersionResult]

    var body: some View {
        HStack(spacing: Space.md) {
            ForEach(versions, id: \.version) { result in
                HStack(spacing: Space.xs) {
                    Text(verbatim: result.version.name)
                    Image(systemName: result.opens ? "checkmark" : "xmark")
                        .foregroundStyle(result.opens ? .green : .red)
                        .accessibilityLabel(result.opens ? Text("works") : Text("fails"))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// The diagnosis of a site (S-101): one line with an icon. With several
/// sites, the ones it applies to are listed under it.
struct BlockVerdictLine: View {
    let kind: BlockKind
    var sites: [String] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: kind.symbol)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(kind.message)
                    .fixedSize(horizontal: false, vertical: true)
                if !sites.isEmpty {
                    Text(verbatim: sites.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var color: AnyShapeStyle {
        switch kind {
        case .dns: AnyShapeStyle(.orange)
        case .ip: AnyShapeStyle(.red)
        case .dpi: AnyShapeStyle(Palette.accentText)
        case .none: AnyShapeStyle(.green)
        }
    }
}

private struct OutcomeLabel: View {
    let outcome: FinderProbe.Outcome

    var body: some View {
        switch outcome {
        case .ok(let status, let ms):
            Label("Opens · \(status) · \(ms) ms", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .monospacedDigit()
        case .failed(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

#if DEBUG
/// Sample finder states for simulator screenshots: launch with
/// ZAPRET_FINDER_SAMPLE=start, progress, or verdict; the Overview page then opens the finder.
enum FinderSample: String {
    case start, progress, verdict

    static var current: FinderSample? {
        ProcessInfo.processInfo.environment["ZAPRET_FINDER_SAMPLE"].flatMap(FinderSample.init)
    }
}
#endif
