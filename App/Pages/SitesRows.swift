import SwiftUI

/// A site or IP range in My list or Never Touch, with its on/off box.
struct SiteRow: View {
    let entry: SiteEntry
    let editing: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            if !editing {
                CheckBox(isOn: entry.isEnabled, action: toggle)
            }
            Image(systemName: entry.isExcluded ? "hand.raised" : entry.isAddress ? "number" : "globe")
                .foregroundStyle(entry.isEnabled ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.tertiary))
                .frame(width: 24)
            Text(entry.domain)
                .foregroundStyle(entry.isEnabled ? .primary : .secondary)
        }
    }
}

/// A subscribed list: its name, how many entries it has, and when it was
/// last downloaded, or why the last download failed.
struct SubscriptionRow: View {
    @Environment(AppModel.self) private var model
    let subscription: ListSubscription

    private var isUpdating: Bool { model.lists.updating.contains(subscription.uuid) }

    var body: some View {
        HStack(spacing: Space.md) {
            CheckBox(isOn: subscription.isEnabled) {
                model.setSubscriptionEnabled(subscription, !subscription.isEnabled)
            }
            Image(systemName: subscription.kind == .addresses ? "number" : "link")
                .foregroundStyle(subscription.isEnabled ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.tertiary))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(subscription.displayName)
                        .foregroundStyle(subscription.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    Group {
                        if subscription.kind == .addresses {
                            Text("\(subscription.count) IP addresses")
                        } else {
                            Text("\(subscription.count) sites")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                }
                status
                    .font(.caption)
                    .lineLimit(2)
            }
            if isUpdating {
                ProgressView()
            } else {
                Button("Update Now", systemImage: "arrow.clockwise") {
                    Task { await model.lists.update(subscription.uuid) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.accentText)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if isUpdating {
            Text("Downloading…").foregroundStyle(.secondary)
        } else if let error = subscription.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let date = subscription.lastUpdated {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("Updated \(date, format: .relative(presentation: .named, unitsStyle: .wide))")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A site tpws added to the automatic list, with a button to keep it in
/// My list and a menu with the other actions.
struct AutoSiteRow: View {
    @Environment(AppModel.self) private var model
    let site: String

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "wand.and.sparkles")
                .foregroundStyle(Palette.accentText)
                .frame(width: 24)
            Text(site)
            Spacer()
            Button("Move to My List", systemImage: "plus.circle") { model.moveAutoSites([site], excluded: false) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.accentText)
            Menu {
                Button("Move to My List", systemImage: "plus.circle") { model.moveAutoSites([site], excluded: false) }
                Button("Move to Never Touch", systemImage: "hand.raised") { model.moveAutoSites([site], excluded: true) }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteAutoSites([site]) }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Palette.accentText)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// The Mac's checkbox, as a tappable square.
private struct CheckBox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(isOn ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isOn ? "Turn off" : "Turn on")
    }
}
