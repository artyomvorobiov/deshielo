import SwiftUI

struct RootView: View {
    @Environment(\.catalog) private var catalog
    @Environment(Router.self) private var router
    @Environment(ShoppingStore.self) private var shopping
    @Environment(TimerCenter.self) private var timers

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.todayPath) {
                TodayView()
                    .routeDestinations()
            }
            .tabItem { Label("Сегодня", systemImage: "sun.max") }
            .tag(AppTab.today)

            NavigationStack(path: $router.explorePath) {
                ExploreView()
                    .routeDestinations()
            }
            .tabItem { Label("Рецепты", systemImage: "book") }
            .tag(AppTab.explore)

            NavigationStack(path: $router.shoppingPath) {
                ShoppingListView()
                    .routeDestinations()
            }
            .tabItem { Label("Покупки", systemImage: "cart") }
            .badge(shopping.uncheckedCount)
            .tag(AppTab.shopping)

            NavigationStack(path: $router.profilePath) {
                ProfileView()
                    .routeDestinations()
            }
            .tabItem { Label("Моё", systemImage: "person.crop.circle") }
            .tag(AppTab.profile)
        }
        .fullScreenCover(item: $router.cooking) { request in
            if let recipe = catalog.recipe(request.recipeID) {
                CookingModeView(recipe: recipe, servings: request.servings ?? recipe.servings)
            }
        }
        .sensoryFeedback(.success, trigger: timers.finishedCount)
        .alert("Таймер сработал",
               isPresented: Binding(get: { timers.finished != nil },
                                    set: { if !$0 { timers.finished = nil } }),
               presenting: timers.finished) { _ in
            Button("Хорошо", role: .cancel) {}
        } message: { timer in
            Text("\(timer.label) — \(timer.recipeTitle)")
        }
    }
}

/// Сопоставление маршрутов и экранов — одно для всех вкладок.
struct RouteDestinations: ViewModifier {
    @Environment(\.catalog) private var catalog

    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            destination(for: route)
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .recipe(let id):
            if let recipe = catalog.recipe(id) {
                RecipeDetailView(recipe: recipe)
            } else {
                ContentUnavailableView("Рецепт не найден", systemImage: "questionmark.circle")
            }
        case .collection(let id):
            if let collection = catalog.collection(id) {
                CollectionDetailView(collection: collection)
            }
        case .chef(let id):
            if let chef = catalog.chef(id) {
                ChefDetailView(chef: chef)
            }
        case .country(let code):
            if let country = catalog.country(code) {
                CountryDetailView(country: country)
            }
        case .allRecipes:
            AllRecipesView()
        case .tasteMap:
            TasteMapView()
        case .timeMachine:
            TimeMachineView()
        case .fridge:
            FridgeView()
        case .converter:
            ConverterView()
        case .glossary:
            GlossaryView()
        case .passport:
            PassportView()
        case .journal:
            JournalView()
        case .favorites:
            FavoritesView()
        case .mealPlan:
            MealPlanView()
        case .settings:
            SettingsView()
        }
    }
}

extension View {
    func routeDestinations() -> some View {
        modifier(RouteDestinations())
    }
}
