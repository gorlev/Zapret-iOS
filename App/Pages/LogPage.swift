import SwiftUI

/// tpws's live output, and the tunnel's own lines, like ZapretMac's Log page.
struct LogPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var errorsOnly = false
    @State private var source: Source = .tpws

    enum Source: Hashable { case tpws, tunnel }

    private var lines: [LogLine] {
        model.logLines.filter { line in
            (!errorsOnly || line.kind == .error)
                && (filter.isEmpty || line.text.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        Group {
            switch source {
            case .tpws:
                if lines.isEmpty {
                    ContentUnavailableView(model.isOn ? "Nothing yet" : "The bypass is off",
                                           systemImage: "text.alignleft",
                                           description: Text(model.isOn ? "tpws writes a line for every connection." : "Turn it on to see what tpws does."))
                } else {
                    ScrollViewReader { proxy in
                        List(lines) { line in
                            Text(line.text)
                                .font(.caption.monospaced())
                                .foregroundStyle(color(line.kind))
                                .textSelection(.enabled)
                                .listRowInsets(EdgeInsets(top: 2, leading: Space.lg, bottom: 2, trailing: Space.lg))
                                .id(line.id)
                        }
                        .listStyle(.plain)
                        .onChange(of: model.logLines.count) {
                            if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            case .tunnel:
                List(model.tunnelLog.indices, id: \.self) { i in
                    Text(model.tunnelLog[i]).font(.caption.monospaced()).textSelection(.enabled)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $filter, prompt: "Filter by site or text")
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Source", selection: $source) {
                    Text("tpws").tag(Source.tpws)
                    Text("Tunnel").tag(Source.tunnel)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Toggle("Errors Only", systemImage: "exclamationmark.triangle", isOn: $errorsOnly)
                    Button("Copy Command", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = (try? TunnelConfig.load())?.tpwsArguments.joined(separator: " ")
                    }
                    ShareLink(item: model.logLines.map(\.text).joined(separator: "\n"))
                    Button("Clear", systemImage: "trash", role: .destructive) { model.clearLog() }
                }
            }
        }
        .onAppear { model.readLog() }
    }

    private func color(_ kind: LogLine.Kind) -> Color {
        switch kind {
        case .error: .red
        case .target: Palette.accentText
        case .connection: .primary
        case .info: .secondary
        }
    }
}
