import Foundation

/// Идентификаторы виджетов — общие для приложения (перезагрузка) и расширения.
enum WidgetKind {
    static let recipeOfTheDay = "RecipeOfTheDay"
    static let shoppingList = "ShoppingList"
    static let passport = "Passport"
}

/// Ссылки вида deshielo://recipe/<id>, которые открывают нужный экран (из виджетов, Spotlight, Siri).
enum DeepLink: Hashable, Sendable {
    case today
    case recipe(String)
    case cook(String)
    case recipeOfTheDay
    case shopping
    case passport
    /// Рецепт из сообщества: deshielo://community/<id>.
    case communityRecipe(String)
    /// Винная и чайная карта: deshielo://drinks.
    case drinks
    /// deshielo://tea/<id>, deshielo://grape/<id>, deshielo://wine-region/<id>, deshielo://wine-style/<id>.
    case tea(String)
    case grape(String)
    case wineRegion(String)
    case wineStyle(String)
    /// Дегустационный дневник: deshielo://tastings.
    case tastings

    static let scheme = "deshielo"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case .recipe(let id):
            components.host = "recipe"
            components.path = "/\(id)"
        case .cook(let id):
            components.host = "cook"
            components.path = "/\(id)"
        case .recipeOfTheDay:
            components.host = "recipe-of-the-day"
        case .shopping:
            components.host = "shopping"
        case .passport:
            components.host = "passport"
        case .communityRecipe(let id):
            components.host = "community"
            components.path = "/\(id)"
        case .drinks:
            components.host = "drinks"
        case .tea(let id):
            components.host = "tea"
            components.path = "/\(id)"
        case .grape(let id):
            components.host = "grape"
            components.path = "/\(id)"
        case .wineRegion(let id):
            components.host = "wine-region"
            components.path = "/\(id)"
        case .wineStyle(let id):
            components.host = "wine-style"
            components.path = "/\(id)"
        case .tastings:
            components.host = "tastings"
        }
        return components.url ?? URL(fileURLWithPath: "/")
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host else { return nil }
        let id = url.pathComponents.dropFirst().first
        switch host {
        case "today": self = .today
        case "recipe-of-the-day": self = .recipeOfTheDay
        case "shopping": self = .shopping
        case "passport": self = .passport
        case "drinks": self = .drinks
        case "tastings": self = .tastings
        case "recipe":
            guard let id else { return nil }
            self = .recipe(id)
        case "cook":
            guard let id else { return nil }
            self = .cook(id)
        case "community":
            guard let id else { return nil }
            self = .communityRecipe(id)
        case "tea":
            guard let id else { return nil }
            self = .tea(id)
        case "grape":
            guard let id else { return nil }
            self = .grape(id)
        case "wine-region":
            guard let id else { return nil }
            self = .wineRegion(id)
        case "wine-style":
            guard let id else { return nil }
            self = .wineStyle(id)
        default:
            return nil
        }
    }
}
