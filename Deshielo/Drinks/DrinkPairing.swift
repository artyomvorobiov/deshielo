import Foundation
import SwiftUI

/// Напиток, подобранный к рецепту.
struct DrinkSuggestion: Hashable, Sendable {
    /// Идентификатор стиля вина или чая.
    let id: String
    let score: Int
    /// Продукты рецепта, на которые сработало правило, — в порядке ингредиентов.
    let matched: [String]
    /// Напиток из той же страны, что и блюдо.
    let isLocal: Bool
    /// Ни одно правило не набрало очков — взят запасной вариант для сладкого или для категории.
    let isFallback: Bool
}

/// Подбор вина и чая к рецепту. Правила лежат в wine.json и tea.json (блок pairing), а здесь — как их считать:
///
/// - продукты рецепта — обязательные ингредиенты, кроме базовых (соль, масло, вода) и «Для подачи»;
/// - продукт из правила даёт 3 очка, если он среди четырёх главных ингредиентов, иначе 2
///   (мука, масло, яйца, молоко, лук и чеснок главными не считаются); учитываются три лучших совпадения;
/// - категория блюда — +2, страна — +3, техника из шагов — +1, продукт из `avoid` — −5;
/// - напиток советуется от 3 очков; при равенстве выигрывает напиток той же страны, затем — первый в файле;
/// - к сладкому (десерты и выпечка, где от 50 г сахара, мёда или варенья, или есть шоколад)
///   подходят только правила с `sweets: true`, к остальным блюдам — только без него;
/// - вино не советуется к завтракам и напиткам, чай — к напиткам.
///
/// Тот же алгоритм описан в docs/CONTENT.md — меняйте их вместе.
enum DrinkPairing {
    static let threshold = 3

    /// Продукты, которые есть почти везде и не определяют вкус блюда.
    static let basics: Set<String> = ["flour", "butter", "egg", "milk", "onion", "garlic", "yeast",
                                      "baking-powder", "baking-soda", "starch"]
    static let sweeteners: Set<String> = ["sugar", "powdered-sugar", "brown-sugar", "honey", "jam", "apricot-jam",
                                          "condensed-milk", "maple-syrup"]
    static let chocolate: Set<String> = ["chocolate", "cocoa"]

    /// Что в рецепте важно для подбора.
    struct Profile: Sendable {
        let category: RecipeCategory
        let country: String?
        /// Ключи продуктов в порядке ингредиентов, без повторов.
        let keys: [String]
        let keySet: Set<String>
        /// Четыре главных продукта.
        let main: Set<String>
        let techniques: Set<String>
        let isSweet: Bool

        init(recipe: Recipe, catalog: Catalog) {
            category = recipe.category
            country = recipe.country
            var keys: [String] = []
            for ingredient in recipe.ingredients {
                guard let key = ingredient.key, !ingredient.optional, ingredient.group != "Для подачи",
                      catalog.pantryItem(key)?.staple != true, !keys.contains(key) else { continue }
                keys.append(key)
            }
            self.keys = keys
            keySet = Set(keys)
            main = Set(keys.filter { !DrinkPairing.basics.contains($0) }.prefix(4))
            techniques = Set(recipe.steps.flatMap(\.techniques))
            isSweet = DrinkPairing.isSweet(recipe)
        }
    }

    struct Score: Sendable {
        let value: Int
        let matched: [String]
        let isLocal: Bool
    }

    /// Десерт или сладкая выпечка.
    static func isSweet(_ recipe: Recipe) -> Bool {
        switch recipe.category {
        case .dessert:
            return true
        case .baking:
            var grams = 0.0
            for ingredient in recipe.ingredients {
                guard let key = ingredient.key else { continue }
                if chocolate.contains(key) { return true }
                guard sweeteners.contains(key), let amount = ingredient.amount else { continue }
                switch ingredient.measureUnit {
                case .g, .ml: grams += amount
                case .kg, .l: grams += amount * 1000
                case .tbsp: grams += amount * 15
                case .tsp: grams += amount * 5
                default: break
                }
            }
            return grams >= 50
        default:
            return false
        }
    }

    static func score(_ rule: DrinkPairingRule, _ profile: Profile) -> Score {
        let matched = profile.keys.filter { rule.keys.contains($0) }
        let weights = matched.map { profile.main.contains($0) ? 3 : 2 }.sorted(by: >)
        var value = weights.prefix(3).reduce(0, +)
        if rule.categories.contains(profile.category) { value += 2 }
        let isLocal = profile.country.map { rule.countries.contains($0) } ?? false
        if isLocal { value += 3 }
        if rule.techniques.contains(where: { profile.techniques.contains($0) }) { value += 1 }
        if rule.avoid.contains(where: { profile.keySet.contains($0) }) { value -= 5 }
        return Score(value: value, matched: matched, isLocal: isLocal)
    }

    /// Лучшее правило от порога. При равенстве — местный напиток, затем — первый по порядку.
    private static func best(_ rules: [(id: String, rule: DrinkPairingRule)], _ profile: Profile) -> DrinkSuggestion? {
        var best: DrinkSuggestion?
        for (id, rule) in rules {
            let result = score(rule, profile)
            guard result.value >= threshold else { continue }
            if let current = best,
               (result.value, result.isLocal ? 1 : 0) <= (current.score, current.isLocal ? 1 : 0) { continue }
            best = DrinkSuggestion(id: id, score: result.value, matched: result.matched, isLocal: result.isLocal,
                                   isFallback: false)
        }
        return best
    }

    static func allowsWine(_ profile: Profile) -> Bool {
        profile.category != .breakfast && profile.category != .drink
    }

    static func allowsTea(_ profile: Profile) -> Bool {
        profile.category != .drink
    }

    static func wine(for profile: Profile, in drinks: DrinkCatalog) -> DrinkSuggestion? {
        guard allowsWine(profile) else { return nil }
        let rules = drinks.wine.styles
            .filter { $0.pairing.sweets == profile.isSweet }
            .map { (id: $0.id, rule: $0.pairing) }
        if let suggestion = best(rules, profile) { return suggestion }
        guard profile.isSweet, let id = drinks.wine.fallback["sweets"], drinks.style(id) != nil else { return nil }
        return DrinkSuggestion(id: id, score: 0, matched: [], isLocal: false, isFallback: true)
    }

    static func tea(for profile: Profile, in drinks: DrinkCatalog) -> DrinkSuggestion? {
        guard allowsTea(profile) else { return nil }
        let rules = drinks.tea.teas.map { (id: $0.id, rule: $0.pairing) }
        if let suggestion = best(rules, profile) { return suggestion }
        let fallback = profile.isSweet ? drinks.tea.fallback["sweets"] : drinks.tea.fallback[profile.category.rawValue]
        guard let id = fallback, drinks.tea(id) != nil else { return nil }
        return DrinkSuggestion(id: id, score: 0, matched: [], isLocal: false, isFallback: true)
    }
}

/// Пары «рецепт — напиток» для всего каталога. Считаются один раз: обратные списки
/// («к чему подать этот чай») нужны на экранах напитков.
struct DrinkPairings: Sendable {
    let catalog: Catalog
    let drinks: DrinkCatalog

    private let profiles: [String: DrinkPairing.Profile]
    private let wineByRecipe: [String: DrinkSuggestion]
    private let teaByRecipe: [String: DrinkSuggestion]

    init(catalog: Catalog, drinks: DrinkCatalog) {
        self.catalog = catalog
        self.drinks = drinks
        var profiles: [String: DrinkPairing.Profile] = [:]
        var wine: [String: DrinkSuggestion] = [:]
        var tea: [String: DrinkSuggestion] = [:]
        for recipe in catalog.recipes {
            let profile = DrinkPairing.Profile(recipe: recipe, catalog: catalog)
            profiles[recipe.id] = profile
            wine[recipe.id] = DrinkPairing.wine(for: profile, in: drinks)
            tea[recipe.id] = DrinkPairing.tea(for: profile, in: drinks)
        }
        self.profiles = profiles
        wineByRecipe = wine
        teaByRecipe = tea
    }

    static let bundled = DrinkPairings(catalog: .bundled, drinks: .bundled)

    /// Вино к рецепту. Рецепты не из каталога (из сообщества) считаются на лету.
    func wine(for recipe: Recipe) -> DrinkSuggestion? {
        if catalog.recipe(recipe.id) != nil { return wineByRecipe[recipe.id] }
        return DrinkPairing.wine(for: DrinkPairing.Profile(recipe: recipe, catalog: catalog), in: drinks)
    }

    func tea(for recipe: Recipe) -> DrinkSuggestion? {
        if catalog.recipe(recipe.id) != nil { return teaByRecipe[recipe.id] }
        return DrinkPairing.tea(for: DrinkPairing.Profile(recipe: recipe, catalog: catalog), in: drinks)
    }

    /// Рецепты к стилю вина: сначала те, к которым он лучший выбор, затем — подходящие по продуктам.
    func recipes(forStyle style: WineStyle, limit: Int = 12) -> [Recipe] {
        recipes(for: style.pairing, id: style.id, chosen: wineByRecipe, limit: limit) { profile in
            DrinkPairing.allowsWine(profile) && profile.isSweet == style.pairing.sweets
        }
    }

    /// Рецепты к сорту винограда — по его стилям.
    func recipes(forGrape grape: Grape, limit: Int = 12) -> [Recipe] {
        let styles = drinks.styles(of: grape)
        var seen: Set<String> = []
        var result: [Recipe] = []
        // По очереди из каждого стиля, чтобы у сорта с несколькими стилями были блюда ко всем.
        let lists = styles.map { recipes(forStyle: $0, limit: limit) }
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count {
                let recipe = list[index]
                if seen.insert(recipe.id).inserted {
                    result.append(recipe)
                }
            }
        }
        return Array(result.prefix(limit))
    }

    func recipes(forTea tea: Tea, limit: Int = 12) -> [Recipe] {
        recipes(for: tea.pairing, id: tea.id, chosen: teaByRecipe, limit: limit, allows: DrinkPairing.allowsTea)
    }

    private func recipes(for rule: DrinkPairingRule, id: String, chosen: [String: DrinkSuggestion], limit: Int,
                         allows: (DrinkPairing.Profile) -> Bool) -> [Recipe] {
        var scored: [(recipe: Recipe, chosen: Bool, score: Int)] = []
        for recipe in catalog.recipes {
            guard let profile = profiles[recipe.id], allows(profile) else { continue }
            let isChosen = chosen[recipe.id]?.id == id
            let score = DrinkPairing.score(rule, profile)
            // Без совпавших продуктов блюдо попадает в список, только если напиток для него — лучший выбор.
            guard isChosen || (score.value >= DrinkPairing.threshold && !score.matched.isEmpty) else { continue }
            scored.append((recipe: recipe, chosen: isChosen, score: score.value))
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.chosen != rhs.chosen { return lhs.chosen }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return DailyPick.stableHash(lhs.recipe.id) < DailyPick.stableHash(rhs.recipe.id)
            }
            .prefix(limit)
            .map(\.recipe)
    }

    /// Названия совпавших продуктов: «говядина, говяжий бульон».
    func ingredientNames(_ suggestion: DrinkSuggestion, limit: Int = 3) -> [String] {
        suggestion.matched.prefix(limit).compactMap { key in
            catalog.pantryItem(key).map { $0.name.lowercasedFirst }
        }
    }
}

extension String {
    /// «Говядина» → «говядина» — для перечислений внутри фразы.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

private struct PairingsKey: EnvironmentKey {
    static let defaultValue = DrinkPairings.bundled
}

extension EnvironmentValues {
    /// Пары «рецепт — напиток» для каталога из бандла.
    var pairings: DrinkPairings {
        get { self[PairingsKey.self] }
        set { self[PairingsKey.self] = newValue }
    }
}
