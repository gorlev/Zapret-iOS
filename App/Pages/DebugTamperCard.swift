import SwiftUI

// TEMPORARY (debug): shows how often tpws changed the first packets, read from
// its log. Not for the finished app: delete this file, its line in
// OverviewPage.swift, and the debug counters in AppModel.swift.
struct DebugTamperCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "ladybug")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Changed by tpws").font(.callout.weight(.medium))
                Text("Debug only. Counts log lines, so turn the bypass on and open some sites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Splits \(model.debugSplits)")
                Text("TLS records \(model.debugTLSRecords)")
            }
            .font(.callout.monospacedDigit())
            .contentTransition(.numericText())
        }
        .padding(Space.lg)
        .card()
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
