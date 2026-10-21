#if DEBUG
import SwiftUI

/// Демо-данные для скриншотов и UI-тестов. Только в отладочной сборке.
/// Аргументы запуска:
/// - `-DemoData` — заполнить избранное, дневник, меню, «холодильник» и список покупок;
/// - `-DemoDark` — принудительно включить тёмную тему.
enum DemoData {
    static let dataArgument = "-DemoData"
    static let darkArgument = "-DemoDark"

    static var colorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains(darkArgument) ? .dark : nil
    }

    /// Вызывается до создания хранилищ, поэтому они сразу читают демо-данные.
    static func seedIfRequested(catalog: Catalog = .bundled) {
        guard ProcessInfo.processInfo.arguments.contains(dataArgument) else { return }
        ProfileStorage.save(profile(catalog: catalog))
        ShoppingListStorage.save(shoppingList(catalog: catalog))
    }

    private static func profile(catalog: Catalog) -> UserProfile {
        let now = Date()
        func day(_ offset: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
        }
        let cooked: [(id: String, daysAgo: Int, rating: Int?)] = [
            ("syrniki", 1, 5), ("carbonara", 3, 5), ("khachapuri-adjarian", 6, 4), ("plov", 9, 5),
            ("libum", 14, 4), ("creme-brulee", 20, 5), ("pho-bo", 27, nil)
        ]

        var profile = UserProfile()
        profile.favorites = ["beef-wellington", "tuhu", "pho-bo", "tiramisu"].filter { catalog.recipe($0) != nil }
        profile.cooked = cooked.compactMap { entry -> CookedEntry? in
            guard catalog.recipe(entry.id) != nil else { return nil }
            return CookedEntry(recipeID: entry.id, date: day(-entry.daysAgo), rating: entry.rating)
        }
        profile.notes["carbonara"] = "В следующий раз — больше чёрного перца и чуть меньше сыра."
        profile.mealPlan = [
            DayKey.make(day(0)): ["shakshuka"],
            DayKey.make(day(1)): ["boeuf-bourguignon"],
            DayKey.make(day(3)): ["pelmeni", "shchi"]
        ]
        profile.pantry = ["egg", "tvorog", "flour", "milk", "butter", "onion", "potato", "sour-cream", "carrot"]
        profile.recent = ["beef-wellington", "tuhu", "carbonara"]
        return profile
    }

    private static func shoppingList(catalog: Catalog) -> ShoppingList {
        var items: [ShoppingItem] = []
        for id in ["boeuf-bourguignon", "tiramisu"] {
            guard let recipe = catalog.recipe(id) else { continue }
            let recipeItems = ShoppingMerger.items(for: recipe, scale: 1, catalog: catalog,
                                                   includeStaples: false, onlyIndices: nil)
            ShoppingMerger.merge(recipeItems, into: &items)
        }
        ShoppingMerger.merge([ShoppingItem(name: "Хлеб бородинский", aisle: .bakery)], into: &items)
        for index in items.indices where index % 4 == 1 {
            items[index].isChecked = true
        }
        return ShoppingList(items: items)
    }
}
#endif
