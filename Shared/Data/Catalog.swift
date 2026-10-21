import Foundation

/// Весь контент приложения: рецепты и справочники. Неизменяемый, загружается из JSON в бандле.
struct Catalog: Sendable {
    let recipes: [Recipe]
    let collections: [RecipeCollection]
    let chefs: [Chef]
    let countries: [Country]
    let eras: [Era]
    let glossary: [GlossaryTerm]
    let facts: [FoodFact]
    let seasons: [SeasonMonth]
    let delivery: [DeliveryService]
    let measures: MeasuresBook
    let pantry: [PantryItem]

    private let recipesByID: [String: Recipe]
    private let chefsByID: [String: Chef]
    private let countriesByCode: [String: Country]
    private let termsByID: [String: GlossaryTerm]
    private let pantryByKey: [String: PantryItem]
    private let searchIndex: [String: SearchEntry]

    init(recipes: [Recipe],
         collections: [RecipeCollection] = [],
         chefs: [Chef] = [],
         countries: [Country] = [],
         eras: [Era] = [],
         glossary: [GlossaryTerm] = [],
         facts: [FoodFact] = [],
         seasons: [SeasonMonth] = [],
         delivery: [DeliveryService] = [],
         measures: MeasuresBook = .empty,
         pantry: [PantryItem] = []) {
        self.recipes = recipes
        self.collections = collections
        self.chefs = chefs
        self.countries = countries
        self.eras = eras.sorted { $0.fromYear < $1.fromYear }
        self.glossary = glossary.sorted { $0.term.localizedCompare($1.term) == .orderedAscending }
        self.facts = facts
        self.seasons = seasons
        self.delivery = delivery
        self.measures = measures
        self.pantry = pantry

        recipesByID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        chefsByID = Dictionary(chefs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        countriesByCode = Dictionary(countries.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        termsByID = Dictionary(glossary.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pantryIndex = Dictionary(pantry.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        pantryByKey = pantryIndex

        var index: [String: SearchEntry] = [:]
        for recipe in recipes {
            let chefName = recipe.chef.flatMap { id in chefs.first { $0.id == id }?.name } ?? ""
            let countryName = recipe.country.flatMap { code in countries.first { $0.code == code }?.name } ?? ""
            index[recipe.id] = SearchEntry(
                title: recipe.title.searchNormalized,
                secondary: [recipe.subtitle ?? "", recipe.origin ?? "", chefName, countryName,
                            recipe.category.title, recipe.yearLabel ?? ""]
                    .joined(separator: " ").searchNormalized,
                ingredients: recipe.ingredients.map { ingredient in
                    let pantryName = ingredient.key.flatMap { pantryIndex[$0]?.name } ?? ""
                    return "\(ingredient.name) \(pantryName)"
                }.joined(separator: " ").searchNormalized,
                text: "\(recipe.summary) \(recipe.story)".searchNormalized
            )
        }
        searchIndex = index
    }

    static let empty = Catalog(recipes: [])

    /// Каталог из бандла. В приложении и виджетах загружается один раз.
    static let bundled: Catalog = {
        do {
            return try CatalogLoader.load(from: .main)
        } catch {
            print("Deshielo: не удалось загрузить каталог — \(error)")
            return .empty
        }
    }()

    // MARK: - Поиск по идентификаторам

    func recipe(_ id: String?) -> Recipe? { id.flatMap { recipesByID[$0] } }
    func chef(_ id: String?) -> Chef? { id.flatMap { chefsByID[$0] } }
    func country(_ code: String?) -> Country? { code.flatMap { countriesByCode[$0] } }
    func term(_ id: String) -> GlossaryTerm? { termsByID[id] }
    func pantryItem(_ key: String?) -> PantryItem? { key.flatMap { pantryByKey[$0] } }
    func collection(_ id: String) -> RecipeCollection? { collections.first { $0.id == id } }

    func era(for year: Int?) -> Era? {
        guard let year else { return nil }
        return eras.first { $0.contains(year) }
    }

    func season(for month: Int) -> SeasonMonth? { seasons.first { $0.month == month } }

    // MARK: - Подборки

    func recipes(inCollection id: String) -> [Recipe] {
        if collection(id)?.showsCountries == true {
            return recipes.filter { $0.country != nil }
        }
        let list = recipes.filter { $0.collections.contains(id) }
        if id == "history" {
            return list.sorted { ($0.year ?? .max) < ($1.year ?? .max) }
        }
        return list
    }

    func recipes(byChef id: String) -> [Recipe] {
        recipes.filter { $0.chef == id }.sorted { ($0.year ?? .max) < ($1.year ?? .max) }
    }

    func recipes(inCountry code: String) -> [Recipe] {
        recipes.filter { $0.country == code }
    }

    func recipes(usingTechnique id: String) -> [Recipe] {
        recipes.filter { recipe in recipe.steps.contains { $0.techniques.contains(id) } }
    }

    /// Рецепты с датой — для «Машины времени», по возрастанию года.
    var datedRecipes: [Recipe] {
        recipes.filter { $0.year != nil }.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
    }

    /// Страны, у которых есть хотя бы один рецепт.
    var countriesWithRecipes: [Country] {
        let used = Set(recipes.compactMap(\.country))
        return countries.filter { used.contains($0.code) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Шефы, у которых есть рецепты, в хронологическом порядке.
    var chefsWithRecipes: [Chef] {
        let used = Set(recipes.compactMap(\.chef))
        return chefs.filter { used.contains($0.id) }
    }

    /// Рецепты, в которых есть продукты сезона, — от самых «сезонных».
    func seasonalRecipes(month: Int, limit: Int = 8) -> [Recipe] {
        guard let keys = season(for: month).map({ Set($0.keys) }), !keys.isEmpty else { return [] }
        var scored: [(recipe: Recipe, score: Int)] = []
        for recipe in recipes {
            let recipeKeys = Set(recipe.ingredients.compactMap(\.key))
            let score = recipeKeys.intersection(keys).count
            if score > 0 {
                scored.append((recipe: recipe, score: score))
            }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : DailyPick.stableHash($0.recipe.id) < DailyPick.stableHash($1.recipe.id) }
            .prefix(limit)
            .map(\.recipe)
    }

    // MARK: - Текстовый поиск

    /// Поиск по названию, происхождению, шефу, стране, ингредиентам и описанию.
    /// Каждое слово запроса должно где-то встретиться; совпадения в названии важнее.
    func search(_ query: String) -> [Recipe] {
        let tokens = query.searchNormalized
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return recipes }

        var results: [(recipe: Recipe, score: Int)] = []
        for recipe in recipes {
            guard let entry = searchIndex[recipe.id] else { continue }
            var score = 0
            var matchedAll = true
            for token in tokens {
                if entry.title.contains(token) {
                    score += entry.title.hasPrefix(token) ? 12 : 10
                } else if entry.secondary.contains(token) {
                    score += 6
                } else if entry.ingredients.contains(token) {
                    score += 4
                } else if entry.text.contains(token) {
                    score += 1
                } else {
                    matchedAll = false
                    break
                }
            }
            if matchedAll { results.append((recipe: recipe, score: score)) }
        }
        return results
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.recipe.title < $1.recipe.title }
            .map(\.recipe)
    }
}

private struct SearchEntry: Sendable {
    let title: String
    let secondary: String
    let ingredients: String
    let text: String
}

extension String {
    /// Строка для поиска: нижний регистр, без диакритики, «ё» = «е».
    var searchNormalized: String {
        lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ru_RU"))
    }
}

enum CatalogError: LocalizedError {
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name): "В бандле нет файла \(name).json"
        }
    }
}

enum CatalogLoader {
    static func load(from bundle: Bundle) throws -> Catalog {
        let decoder = JSONDecoder()

        func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw CatalogError.missingFile(name)
            }
            return try decoder.decode(T.self, from: Data(contentsOf: url))
        }

        let recipeFiles = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("recipes-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !recipeFiles.isEmpty else { throw CatalogError.missingFile("recipes-*") }

        var recipes: [Recipe] = []
        for url in recipeFiles {
            recipes += try decoder.decode([Recipe].self, from: Data(contentsOf: url))
        }

        return Catalog(
            recipes: recipes,
            collections: try decode([RecipeCollection].self, "collections"),
            chefs: try decode([Chef].self, "chefs"),
            countries: try decode([Country].self, "countries"),
            eras: try decode([Era].self, "eras"),
            glossary: try decode([GlossaryTerm].self, "glossary"),
            facts: try decode([FoodFact].self, "facts"),
            seasons: try decode([SeasonMonth].self, "seasonal"),
            delivery: try decode([DeliveryService].self, "delivery"),
            measures: try decode(MeasuresBook.self, "measures"),
            pantry: try decode([PantryItem].self, "pantry")
        )
    }
}
