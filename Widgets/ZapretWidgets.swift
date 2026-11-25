import AppIntents
import SwiftUI
import WidgetKit

@main
struct ZapretWidgets: WidgetBundle {
    var body: some Widget {
        BypassStatusWidget()
        BypassToggleControl()
    }
}

// MARK: - Home Screen and Lock Screen widget

struct BypassEntry: TimelineEntry {
    let date: Date
    let isOn: Bool
    let strategy: String
}

struct BypassWidgetConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Zapret"
}

struct BypassProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BypassEntry {
        BypassEntry(date: .now, isOn: true, strategy: "TLS Record + Split")
    }

    func snapshot(for configuration: BypassWidgetConfig, in context: Context) async -> BypassEntry {
        await entry()
    }

    func timeline(for configuration: BypassWidgetConfig, in context: Context) async -> Timeline<BypassEntry> {
        // The app and the tunnel reload this when the state changes; the refresh is a backstop.
        Timeline(entries: [await entry()], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry() async -> BypassEntry {
        let isOn = await BypassControl.isOn()
        let name = AppGroup.defaults.string(forKey: "strategyName")
            ?? Preset.with(id: AppGroup.defaults.string(forKey: "presetID") ?? Preset.defaultID)?.name
            ?? "Zapret"
        return BypassEntry(date: .now, isOn: isOn, strategy: name)
    }
}

struct BypassStatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "BypassStatus", intent: BypassWidgetConfig.self, provider: BypassProvider()) { entry in
            BypassWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Zapret Bypass")
        .description("Shows whether the bypass is on, and its strategy. Tap to turn it on or off.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private let petrol = Color(red: 0x0B / 255, green: 0x72 / 255, blue: 0x85 / 255)

struct BypassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BypassEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(entry.isOn ? "Bypass on" : "Bypass off", systemImage: "shield.lefthalf.filled")
        case .accessoryCircular:
            Button(intent: ToggleBypassIntent()) {
                Image(systemName: entry.isOn ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 30))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isOn ? "Bypass on" : "Bypass off")
        case .accessoryRectangular:
            Button(intent: ToggleBypassIntent()) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(entry.isOn ? "Bypass on" : "Bypass off", systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                    Text(entry.strategy).font(.caption).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Button(intent: ToggleBypassIntent()) {
                    Image(systemName: "power")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(entry.isOn ? .white : .secondary)
                        .frame(width: 48, height: 48)
                        .background(entry.isOn ? AnyShapeStyle(petrol) : AnyShapeStyle(.quaternary), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(entry.isOn ? "Bypass is on" : "Bypass is off").font(.headline)
                Text(entry.strategy).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Control Center control

struct BypassToggleControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { await BypassControl.isOn() }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.gorlev.zapretios.widgets.bypass", provider: Provider()) { isOn in
            ControlWidgetToggle("Zapret Bypass", isOn: isOn, action: SetBypassIntent()) { isOn in
                Label(isOn ? "On" : "Off", systemImage: "shield.lefthalf.filled")
            }
            .tint(petrol)
        }
        .displayName("Zapret Bypass")
        .description("Turns the Zapret bypass on or off.")
    }
}
