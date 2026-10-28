import SwiftUI

@main
struct DeshieloApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = Router.shared
    @State private var profile: ProfileStore
    @State private var shopping: ShoppingStore
    @State private var timers = TimerCenter()
    @State private var community: CommunityStore
    @State private var tastings: TastingStore

    private let catalog = Catalog.bundled

    init() {
        #if DEBUG
        DemoData.seedIfRequested()
        #endif
        // Фото сообщества сервер отдаёт с долгим сроком хранения — держим их в кеше.
        URLCache.shared = URLCache(memoryCapacity: 48 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        _profile = State(initialValue: ProfileStore())
        _shopping = State(initialValue: ShoppingStore())
        _community = State(initialValue: CommunityStore.make())
        _tastings = State(initialValue: TastingStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.catalog, catalog)
                .environment(router)
                .environment(profile)
                .environment(shopping)
                .environment(timers)
                .environment(community)
                .environment(tastings)
                .tint(Theme.accent)
                #if DEBUG
                .preferredColorScheme(DemoData.colorScheme)
                #endif
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
                    await community.refreshSession()
                    await community.loadCatalogRatings()
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
