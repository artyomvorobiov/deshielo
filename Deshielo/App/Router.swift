import Observation
import SwiftUI

enum AppTab: Hashable {
    case today, explore, shopping, profile
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
}

struct CookingRequest: Identifiable, Hashable {
    let recipeID: String
    let servings: Int?

    var id: String { recipeID }
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
    var shoppingPath: [Route] = []
    var profilePath: [Route] = []
    var cooking: CookingRequest?

    func push(_ route: Route) {
        switch tab {
        case .today: todayPath.append(route)
        case .explore: explorePath.append(route)
        case .shopping: shoppingPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func open(_ link: DeepLink, catalog: Catalog = .bundled) {
        switch link {
        case .today:
            tab = .today
            todayPath = []
        case .recipe(let id):
            guard catalog.recipe(id) != nil else { return }
            tab = .today
            todayPath = [.recipe(id)]
        case .recipeOfTheDay:
            guard let recipe = DailyPick.recipe(in: catalog) else { return }
            tab = .today
            todayPath = [.recipe(recipe.id)]
        case .cook(let id):
            guard catalog.recipe(id) != nil else { return }
            cooking = CookingRequest(recipeID: id, servings: nil)
        case .shopping:
            tab = .shopping
            shoppingPath = []
        case .passport:
            tab = .profile
            profilePath = [.passport]
        }
    }

    func startCooking(_ recipe: Recipe, servings: Int) {
        cooking = CookingRequest(recipeID: recipe.id, servings: servings)
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
