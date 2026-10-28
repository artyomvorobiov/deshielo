#if DEBUG
import SwiftUI

/// Демо-данные для скриншотов и UI-тестов. Только в отладочной сборке.
/// Аргументы запуска:
/// - `-DemoData` — заполнить избранное, дневник, меню, «холодильник» и список покупок;
/// - `-DemoDark` — принудительно включить тёмную тему.
enum DemoData {
    static let dataArgument = "-DemoData"
    static let darkArgument = "-DemoDark"

    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(dataArgument) }

    static var colorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains(darkArgument) ? .dark : nil
    }

    /// Вызывается до создания хранилищ, поэтому они сразу читают демо-данные.
    @MainActor
    static func seedIfRequested(catalog: Catalog = .bundled) {
        guard isEnabled else { return }
        JournalPhotos.deleteAll()
        var demoProfile = profile(catalog: catalog)
        // Пара записей дневника — с «фото результата» (генеративная обложка блюда).
        for index in demoProfile.cooked.indices.prefix(2) {
            if let recipe = catalog.recipe(demoProfile.cooked[index].recipeID) {
                demoProfile.cooked[index].photo = journalPhoto(for: recipe)
            }
        }
        ProfileStorage.save(demoProfile)
        ShoppingListStorage.save(shoppingList(catalog: catalog))
        TastingStorage.save(tastings())
    }

    @MainActor
    private static func journalPhoto(for recipe: Recipe) -> String? {
        let renderer = ImageRenderer(content: DishArtwork(recipe: recipe, showsYear: false).frame(width: 600, height: 600))
        renderer.scale = 1
        return renderer.uiImage.flatMap { JournalPhotos.save($0) }
    }

    /// Дегустационный дневник: два вина и два чая, у части — «фото» (иллюстрация напитка).
    @MainActor
    private static func tastings(drinks: DrinkCatalog = .bundled) -> [Tasting] {
        let now = Date()
        func day(_ offset: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
        }
        func photo<Content: View>(_ content: Content) -> String? {
            let renderer = ImageRenderer(content: content.frame(width: 600, height: 600))
            renderer.scale = 1
            return renderer.uiImage.flatMap { JournalPhotos.save($0) }
        }
        var list = [
            Tasting(kind: .wine, name: "Красностоп", date: day(-2), vintage: 2021, styleID: "red-rich",
                    grapeID: "krasnostop", regionID: "don", rating: 5, aromas: ["вишня", "специи", "черноплодная рябина"],
                    note: "К говядине по-бургундски — отлично. Открыть за час до ужина.", recipeID: "boeuf-bourguignon"),
            Tasting(kind: .tea, name: "Лунцзин весеннего сбора", date: day(-4), teaID: "longjing", rating: 5,
                    aromas: ["каштан", "свежая зелень"], note: "Второй пролив — самый вкусный."),
            Tasting(kind: .wine, name: "Шабли", date: day(-11), vintage: 2022, styleID: "white-light",
                    grapeID: "chardonnay", regionID: "burgundy", rating: 4, aromas: ["яблоко", "лимон"],
                    note: "Свежее, с минеральностью. С устрицами было бы идеально."),
            Tasting(kind: .tea, name: "Иван-чай", date: day(-16), teaID: "ivan-chai", rating: 4,
                    aromas: ["мёд", "сухофрукты"])
        ]
        if let grape = drinks.grape("krasnostop") {
            list[0].photo = photo(DrinkArtwork(grape: grape))
        }
        if let tea = drinks.tea("longjing") {
            list[1].photo = photo(DrinkArtwork(tea: tea))
        }
        return list
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
