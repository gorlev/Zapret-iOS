import SwiftUI
import UIKit

/// Adds the gear button (leading side of the toolbar) that opens Settings as a sheet.
private struct SettingsButton: ViewModifier {
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showing = true }
                }
            }
            .sheet(isPresented: $showing) { SettingsView() }
    }
}

extension View {
    /// A gear button that opens the Settings sheet. Put it on a page with a navigation bar.
    func settingsButton() -> some View { modifier(SettingsButton()) }
}

/// The Mac's Settings tabs (General, Appearance, Advanced, About) as sections of one grouped form.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    private var store = ThemeStore.shared

    var body: some View {
        NavigationStack {
            Form {
                AppearanceSection()
                GeneralSection()
                AdvancedSection()
                AboutSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(store.theme.accent)
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Bindable private var store = ThemeStore.shared

    var body: some View {
        Section {
            AccentPreview()
                .listRowInsets(EdgeInsets(top: Space.md, leading: Space.lg, bottom: Space.md, trailing: Space.lg))
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text("Accent color")
                    Spacer()
                    Text(store.theme.name).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: Space.md)], spacing: Space.md) {
                    ForEach(Theme.all) { theme in
                        AccentSwatch(theme: theme, selected: store.themeID == theme.id) { store.themeID = theme.id }
                    }
                }
            }
            .padding(.vertical, Space.xs)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Light and dark mode follow your iPhone.")
        }
    }
}

/// A small sample of the Overview in the chosen accent. Drawn, not real controls.
private struct AccentPreview: View {
    private let store = ThemeStore.shared
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        let theme = store.theme
        HStack(spacing: Space.lg) {
            Circle()
                .fill(theme.heroFill)
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "power").font(.title2.weight(.semibold)).foregroundStyle(theme.onAccent))
                .shadow(color: theme.accent.opacity(0.4), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Bypass is on").font(.headline)
                HStack(spacing: Space.sm) {
                    Text("TLS Record + Split")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.accentText)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(theme.accent.opacity(0.15), in: Capsule())
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 32, height: 20)
                        .overlay(alignment: .trailing) { Circle().fill(.white).padding(2) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
        .background(Color(uiColor: .systemGroupedBackground), in: shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the accent color")
    }
}

/// One color dot.
private struct AccentSwatch: View {
    let theme: Theme
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Circle()
                .fill(theme.accent)
                .frame(width: 32, height: 32)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.onAccent)
                    }
                }
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - General

private struct GeneralSection: View {
    @Environment(AppModel.self) private var model
    @Bindable private var prefs = AppPrefs.shared

    var body: some View {
        Section {
            Toggle("Turn the bypass on when Zapret opens", isOn: $prefs.startOnLaunch)
            Toggle("Keep the bypass on", isOn: $prefs.keepOn)
                .onChange(of: prefs.keepOn) { Task { await BypassControl.keepOnChanged() } }
        } header: {
            Text("General")
        } footer: {
            Text("While it is on, iOS turns the bypass back on by itself after a dropped connection or a network change. Turning it off in Zapret, Control Center, or Shortcuts stops it until you turn it on again.")
        }
        Section {
            Toggle("Show every connection in the log", isOn: $prefs.verboseLog)
                .onChange(of: prefs.verboseLog) { model.restartIfRunning() }
        } header: {
            Text("Log")
        } footer: {
            Text("Off logs only errors, which also stops the connection count on Overview.")
        }
    }
}

// MARK: - Advanced

private struct AdvancedSection: View {
    @Environment(AppModel.self) private var model
    @Bindable private var prefs = AppPrefs.shared
    @State private var address: NetworkShare.Address?

    var body: some View {
        Section {
            Toggle("Share with devices on this network", isOn: $prefs.shareOnNetwork)
                .onChange(of: prefs.shareOnNetwork) { model.restartIfRunning() }
            if prefs.shareOnNetwork {
                if let address {
                    let text = "\(address.ip):\(TunnelConfig.socksPort)"
                    LabeledContent("SOCKS5 address") {
                        HStack(spacing: Space.sm) {
                            Text(text).monospacedDigit().textSelection(.enabled)
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                    }
                    LabeledContent {
                        QRCode(text: NetworkShare.payload(ip: address.ip, port: TunnelConfig.socksPort))
                    } label: {
                        Text("QR code")
                        Text("Scan it in a proxy app on another device.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Label("No Wi-Fi address. Connect this iPhone to Wi-Fi to share.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Advanced")
        } footer: {
            if prefs.shareOnNetwork {
                Text("While sharing is on, anyone on this Wi-Fi network can use this iPhone's bypass. Use an app that supports SOCKS5 proxies on the other device and enter this address there. Turn the bypass on to start sharing.")
            } else {
                Text("Lets a computer, tablet, or TV on your Wi-Fi use this iPhone as a SOCKS5 proxy. Off by default.")
            }
        }
        .task(id: prefs.shareOnNetwork) {
            // The address changes when the phone changes network: look again every few seconds.
            while !Task.isCancelled, prefs.shareOnNetwork {
                address = NetworkShare.choose(from: NetworkShare.currentAddresses(), preferred: "en0")
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    var body: some View {
        Section {
            LabeledContent("Zapret", value: BuildInfo.appVersion)
            LabeledContent("tpws (zapret)", value: String(BuildInfo.zapretCommit.prefix(10)))
            LabeledContent("hev-socks5-tunnel", value: String(BuildInfo.hevCommit.prefix(10)))
        } header: {
            Text("About")
        } footer: {
            Text("The bypass engine is tpws from zapret by bol-van, MIT license. hev-socks5-tunnel by heiher turns the tunnel's packets into connections, also MIT.")
        }
        Section("Licenses") {
            Link("zapret license", destination: URL(string: "https://github.com/bol-van/zapret/blob/master/docs/LICENSE.txt")!)
            Link("hev-socks5-tunnel license", destination: URL(string: "https://github.com/heiher/hev-socks5-tunnel/blob/master/LICENSE")!)
        }
    }
}
