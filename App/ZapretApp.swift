import SwiftUI

@main
struct ZapretApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.accent)
        }
    }
}

/// The four pages of ZapretMac's sidebar, as tabs on iPhone and a sidebar on iPad.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Page = .overview

    enum Page: Hashable { case overview, strategies, sites, log }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Overview", systemImage: "shield.lefthalf.filled", value: .overview) {
                NavigationStack { OverviewPage() }
            }
            Tab("Strategies", systemImage: "slider.horizontal.3", value: .strategies) {
                NavigationStack { StrategiesPage() }
            }
            Tab("Sites", systemImage: "globe", value: .sites) {
                NavigationStack { SitesPage() }
            }
            .badge(model.scope == .listOnly ? model.includeSites.filter(\.isEnabled).count : 0)
            Tab("Log", systemImage: "text.alignleft", value: .log) {
                NavigationStack { LogPage() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
