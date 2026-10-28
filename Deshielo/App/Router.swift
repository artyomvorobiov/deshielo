import Observation
import SwiftUI

enum AppTab: Hashable {
    case today, explore, community, shopping, profile
}

/// Экраны, на которые можно перейти внутри вкладки.
enum Route: Hashable {
    case recipe(String)
    case collection(String)
    case chef(String)
    case country(String)
    case allRecipes
    case tasteMap
    case timeMachine
    case fridge
    case converter
    case glossary
    case passport
    case journal
    case favorites
    case mealPlan
    case settings
    case communityRecipe(String)
    case communityAccount
    case communityRules
    case drinks
    case wineStyle(String)
    case grape(String)
    case wineRegion(String)
    case teaType(String)
    case tea(String)
    case drinkMap
    case tastings
}

/// Что готовим: рецепт из каталога или из сообщества — поэтому передаётся сам рецепт, а не id.
struct CookingRequest: Identifiable, Hashable {
    let recipe: Recipe
    let servings: Int?

    var id: String { recipe.id }
}

/// Навигация приложения: выбранная вкладка, стеки экранов и режим готовки.
/// Общий экземпляр нужен ссылкам из виджетов, Spotlight и Siri.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    var tab: AppTab = .today
    var todayPath: [Route] = []
    var explorePath: [Route] = []
    var communityPath: [Route] = []
    var shoppingPath: [Route] = []
    var profilePath: [Route] = []
    var cooking: CookingRequest?
    /// Запрос из поиска каталога, который нужно повторить в сообществе.
    var communitySearch: String?

    func push(_ route: Route) {
        switch tab {
        case .today: todayPath.append(route)
        case .explore: explorePath.append(route)
        case .community: communityPath.append(route)
        case .shopping: shoppingPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func open(_ link: DeepLink, catalog: Catalog = .bundled, drinks: DrinkCatalog = .bundled) {
        switch link {
        case .today:
            tab = .today
            todayPath = []
        case .recipe(let id):
            // Таймеры рецептов сообщества ссылаются на «community:<id>».
            if id.hasPrefix(Recipe.communityPrefix) {
                open(.communityRecipe(String(id.dropFirst(Recipe.communityPrefix.count))), catalog: catalog)
                return
            }
            // Таймеры заваривания ссылаются на «tea:<id>».
            if id.hasPrefix(Tea.timerPrefix) {
                open(.tea(String(id.dropFirst(Tea.timerPrefix.count))), catalog: catalog, drinks: drinks)
                return
            }
            guard catalog.recipe(id) != nil else { return }
            tab = .today
            todayPath = [.recipe(id)]
        case .recipeOfTheDay:
            guard let recipe = DailyPick.recipe(in: catalog) else { return }
            tab = .today
            todayPath = [.recipe(recipe.id)]
        case .cook(let id):
            guard let recipe = catalog.recipe(id) else { return }
            cooking = CookingRequest(recipe: recipe, servings: nil)
        case .communityRecipe(let id):
            tab = .community
            communityPath = [.communityRecipe(id)]
        case .shopping:
            tab = .shopping
            shoppingPath = []
        case .passport:
            tab = .profile
            profilePath = [.passport]
        case .drinks:
            tab = .explore
            explorePath = [.drinks]
        case .tea(let id):
            guard drinks.tea(id) != nil else { return }
            tab = .explore
            explorePath = [.drinks, .tea(id)]
        case .grape(let id):
            guard DrinksConfig.showsWine, drinks.grape(id) != nil else { return }
            tab = .explore
            explorePath = [.drinks, .grape(id)]
        case .wineRegion(let id):
            guard DrinksConfig.showsWine, drinks.region(id) != nil else { return }
            tab = .explore
            explorePath = [.drinks, .wineRegion(id)]
        case .wineStyle(let id):
            guard DrinksConfig.showsWine, drinks.style(id) != nil else { return }
            tab = .explore
            explorePath = [.drinks, .wineStyle(id)]
        case .tastings:
            tab = .profile
            profilePath = [.tastings]
        }
    }

    func startCooking(_ recipe: Recipe, servings: Int) {
        cooking = CookingRequest(recipe: recipe, servings: servings)
    }

    /// Повторить поиск из каталога среди рецептов сообщества.
    func searchCommunity(_ text: String) {
        communitySearch = text
        communityPath = []
        tab = .community
    }
}

private struct CatalogKey: EnvironmentKey {
    static let defaultValue = Catalog.bundled
}

extension EnvironmentValues {
    /// Каталог рецептов. По умолчанию — загруженный из бандла.
    var catalog: Catalog {
        get { self[CatalogKey.self] }
        set { self[CatalogKey.self] = newValue }
    }
}

extension String {
    /// nil для пустой или пробельной строки.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
