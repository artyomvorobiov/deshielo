import SwiftUI

@main
struct DeshieloApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = Router.shared
    @State private var profile = ProfileStore()
    @State private var shopping = ShoppingStore()
    @State private var timers = TimerCenter()

    private let catalog = Catalog.bundled

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.catalog, catalog)
                .environment(router)
                .environment(profile)
                .environment(shopping)
                .environment(timers)
                .tint(Theme.accent)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) {
                        router.open(link, catalog: catalog)
                    }
                }
                .onContinueUserActivity("com.apple.corespotlightitem") { activity in
                    if let link = SpotlightIndexer.deepLink(from: activity) {
                        router.open(link, catalog: catalog)
                    }
                }
                .task {
                    let content = catalog
                    Task.detached(priority: .background) {
                        SpotlightIndexer.index(content)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Виджет мог отметить покупки, пока приложение было в фоне.
            shopping.reload()
            profile.reload()
            timers.checkFinished()
        }
    }
}
