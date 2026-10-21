import Foundation

/// Рецепт. Описывается в Shared/Content/recipes-*.json.
/// Декодирование мягкое: необязательные поля могут отсутствовать, неизвестные значения не ломают загрузку.
struct Recipe: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let summary: String
    let story: String
    let collections: [String]
    let chef: String?
    let country: String?
    let origin: String?
    let year: Int?
    let yearLabel: String?
    let category: RecipeCategory
    let difficulty: Int
    let prepMinutes: Int
    let cookMinutes: Int
    let restMinutes: Int
    let servings: Int
    let calories: Int?
    let diets: [Diet]
    let palette: [String]
    /// Имя картинки в Assets (необязательно). Без неё рисуется генеративная обложка.
    let image: String?
    let ingredients: [Ingredient]
    let steps: [RecipeStep]
    let plating: String?
    let pairing: String?
    let tips: [String]
    let source: RecipeSource?

    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Время активной работы и готовки, без ожидания.
    var activeMinutes: Int { prepMinutes + cookMinutes }
    var totalMinutes: Int { prepMinutes + cookMinutes + restMinutes }

    var isHistoric: Bool { collections.contains("history") }

    var difficultyTitle: String {
        switch difficulty {
        case ...1: "Просто"
        case 2: "Средне"
        default: "Сложно"
        }
    }

    /// Ингредиенты, сгруппированные по полю `group` с сохранением порядка.
    var ingredientGroups: [IngredientGroup] {
        var groups: [IngredientGroup] = []
        for (index, ingredient) in ingredients.enumerated() {
            if let last = groups.last, last.title == ingredient.group {
                groups[groups.count - 1].items.append(IndexedIngredient(index: index, ingredient: ingredient))
            } else {
                groups.append(IngredientGroup(title: ingredient.group,
                                              items: [IndexedIngredient(index: index, ingredient: ingredient)]))
            }
        }
        return groups
    }
}

extension Recipe: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, summary, story, collections, chef, country, origin, year, yearLabel
        case category, difficulty, prepMinutes, cookMinutes, restMinutes, servings, calories, diets
        case palette, image, ingredients, steps, plating, pairing, tips, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        story = try c.decodeIfPresent(String.self, forKey: .story) ?? ""
        collections = try c.decodeIfPresent([String].self, forKey: .collections) ?? []
        chef = try c.decodeIfPresent(String.self, forKey: .chef)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        yearLabel = try c.decodeIfPresent(String.self, forKey: .yearLabel)
        category = try c.decodeIfPresent(RecipeCategory.self, forKey: .category) ?? .main
        difficulty = try c.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1
        prepMinutes = try c.decodeIfPresent(Int.self, forKey: .prepMinutes) ?? 0
        cookMinutes = try c.decodeIfPresent(Int.self, forKey: .cookMinutes) ?? 0
        restMinutes = try c.decodeIfPresent(Int.self, forKey: .restMinutes) ?? 0
        let decodedServings = try c.decodeIfPresent(Int.self, forKey: .servings) ?? 1
        servings = max(1, decodedServings)
        calories = try c.decodeIfPresent(Int.self, forKey: .calories)
        let dietNames = try c.decodeIfPresent([String].self, forKey: .diets) ?? []
        diets = dietNames.compactMap(Diet.init(rawValue:))
        palette = try c.decodeIfPresent([String].self, forKey: .palette) ?? []
        image = try c.decodeIfPresent(String.self, forKey: .image)
        ingredients = try c.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        steps = try c.decodeIfPresent([RecipeStep].self, forKey: .steps) ?? []
        plating = try c.decodeIfPresent(String.self, forKey: .plating)
        pairing = try c.decodeIfPresent(String.self, forKey: .pairing)
        tips = try c.decodeIfPresent([String].self, forKey: .tips) ?? []
        source = try c.decodeIfPresent(RecipeSource.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(summary, forKey: .summary)
        try c.encode(story, forKey: .story)
        try c.encode(collections, forKey: .collections)
        try c.encodeIfPresent(chef, forKey: .chef)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(origin, forKey: .origin)
        try c.encodeIfPresent(year, forKey: .year)
        try c.encodeIfPresent(yearLabel, forKey: .yearLabel)
        try c.encode(category, forKey: .category)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(prepMinutes, forKey: .prepMinutes)
        try c.encode(cookMinutes, forKey: .cookMinutes)
        try c.encode(restMinutes, forKey: .restMinutes)
        try c.encode(servings, forKey: .servings)
        try c.encodeIfPresent(calories, forKey: .calories)
        try c.encode(diets.map(\.rawValue), forKey: .diets)
        try c.encode(palette, forKey: .palette)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encode(ingredients, forKey: .ingredients)
        try c.encode(steps, forKey: .steps)
        try c.encodeIfPresent(plating, forKey: .plating)
        try c.encodeIfPresent(pairing, forKey: .pairing)
        try c.encode(tips, forKey: .tips)
        try c.encodeIfPresent(source, forKey: .source)
    }
}

struct Ingredient: Codable, Hashable, Sendable {
    let name: String
    let amount: Double?
    /// Код единицы: g, kg, ml, l, pcs, tbsp, tsp, pinch, clove, bunch, sprig, slice, leaf, stalk, head, toTaste.
    let unit: String?
    /// Ключ продукта из pantry.json — для поиска «Из холодильника» и отделов в списке покупок.
    let key: String?
    let note: String?
    let group: String?
    let optional: Bool

    init(name: String, amount: Double? = nil, unit: String? = nil, key: String? = nil,
         note: String? = nil, group: String? = nil, optional: Bool = false) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.key = key
        self.note = note
        self.group = group
        self.optional = optional
    }

    private enum CodingKeys: String, CodingKey {
        case name, amount, unit, key, note, group, optional
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        group = try c.decodeIfPresent(String.self, forKey: .group)
        optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
    }

    var measureUnit: MeasureUnit? { unit.flatMap(MeasureUnit.init(rawValue:)) }
}

struct IndexedIngredient: Hashable, Sendable {
    let index: Int
    let ingredient: Ingredient
}

struct IngredientGroup: Hashable, Sendable {
    let title: String?
    var items: [IndexedIngredient]
}

struct RecipeStep: Codable, Hashable, Sendable {
    let title: String?
    let text: String
    /// Таймер шага в минутах (может быть дробным).
    let timer: Double?
    /// Температура духовки, масла или воды, °C.
    let temperature: Int?
    /// Идентификаторы техник из glossary.json.
    let techniques: [String]

    private enum CodingKeys: String, CodingKey {
        case title, text, timer, temperature, techniques
    }

    init(title: String?, text: String, timer: Double? = nil, temperature: Int? = nil, techniques: [String] = []) {
        self.title = title
        self.text = text
        self.timer = timer
        self.temperature = temperature
        self.techniques = techniques
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        timer = try c.decodeIfPresent(Double.self, forKey: .timer)
        temperature = try c.decodeIfPresent(Int.self, forKey: .temperature)
        techniques = try c.decodeIfPresent([String].self, forKey: .techniques) ?? []
    }

    var timerSeconds: TimeInterval? { timer.map { $0 * 60 } }
}

/// Историческая справка: откуда рецепт, оригинальный текст и перевод.
struct RecipeSource: Codable, Hashable, Sendable {
    let title: String
    let author: String?
    let date: String?
    /// Точная цитата из источника (на языке оригинала).
    let quote: String?
    let quoteLanguage: String?
    let translation: String?
    /// Пересказ, если точный текст не приводится.
    let retelling: String?
    /// Что изменено в современной адаптации.
    let note: String?
}

enum RecipeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case soup, main, side, salad, dessert, baking, breakfast, drink, snack

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RecipeCategory(rawValue: raw) ?? .main
    }

    var title: String {
        switch self {
        case .soup: "Супы"
        case .main: "Основные блюда"
        case .side: "Гарниры"
        case .salad: "Салаты"
        case .dessert: "Десерты"
        case .baking: "Выпечка"
        case .breakfast: "Завтраки"
        case .drink: "Напитки"
        case .snack: "Закуски"
        }
    }

    var symbol: String {
        switch self {
        case .soup: "mug"
        case .main: "fork.knife"
        case .side: "leaf"
        case .salad: "carrot"
        case .dessert: "birthday.cake"
        case .baking: "oven"
        case .breakfast: "sun.horizon"
        case .drink: "cup.and.saucer"
        case .snack: "sparkles"
        }
    }
}

enum Diet: String, Codable, CaseIterable, Identifiable, Sendable {
    case vegetarian
    case vegan
    case glutenFree = "gluten-free"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vegetarian: "Вегетарианское"
        case .vegan: "Веганское"
        case .glutenFree: "Без глютена"
        }
    }

    var symbol: String {
        switch self {
        case .vegetarian: "leaf"
        case .vegan: "leaf.circle"
        case .glutenFree: "checkmark.seal"
        }
    }
}
