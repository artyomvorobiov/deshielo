import Foundation

/// Автор рецепта или отзыва в сообществе.
struct CommunityAuthor: Hashable, Sendable {
    let id: String
    let name: String
}

/// Ингредиент рецепта сообщества. Те же поля, что в каталоге, только без ключа продукта.
struct CommunityIngredient: Codable, Hashable, Sendable {
    var name: String
    var amount: Double?
    var unit: String?
    var note: String?
    var group: String?
}

struct CommunityStep: Codable, Hashable, Sendable {
    var title: String?
    var text: String
    /// Таймер шага в минутах.
    var timer: Int?

    init(title: String? = nil, text: String, timer: Int? = nil) {
        self.title = title
        self.text = text
        self.timer = timer
    }

    private enum CodingKeys: String, CodingKey {
        case title, text, timer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        timer = try c.decodeIfPresent(Double.self, forKey: .timer).map { Int($0.rounded()) }
    }
}

/// Фото на сервере: оригинал и миниатюра.
struct CommunityPhoto: Identifiable, Hashable, Sendable {
    let name: String
    let url: URL
    let thumbnailURL: URL

    var id: String { name }
}

struct RatingSummary: Hashable, Sendable {
    let average: Double
    let count: Int

    static let empty = RatingSummary(average: 0, count: 0)
}

/// Рецепт, который опубликовал пользователь.
struct CommunityRecipe: Identifiable, Hashable, Sendable {
    let id: String
    let author: CommunityAuthor
    var title: String
    var summary: String
    var story: String
    var category: RecipeCategory
    var country: String?
    var difficulty: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var servings: Int
    var ingredients: [CommunityIngredient]
    var steps: [CommunityStep]
    var photos: [CommunityPhoto]
    var isPublished: Bool
    var isHidden: Bool
    var rating: RatingSummary
    let created: Date

    var totalMinutes: Int { prepMinutes + cookMinutes }
}

/// К какому рецепту относится отзыв: из сообщества или из каталога приложения.
enum ReviewTarget: Hashable, Sendable {
    case community(String)
    case catalog(String)
}

struct CommunityReview: Identifiable, Hashable, Sendable {
    let id: String
    let author: CommunityAuthor
    let target: ReviewTarget
    var rating: Int
    var comment: String
    var photo: CommunityPhoto?
    var isHidden: Bool
    let created: Date
}

struct CommunityUser: Codable, Hashable, Sendable {
    let id: String
    var name: String
    var email: String
}

/// Вход в аккаунт: токен для запросов и данные пользователя. Хранится в Keychain.
struct CommunitySession: Codable, Hashable, Sendable {
    var token: String
    var user: CommunityUser
}

enum CommunitySort: String, CaseIterable, Identifiable, Sendable {
    case newest, best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Новые"
        case .best: "Лучшие"
        }
    }
}

/// Поиск по рецептам сообщества.
struct CommunityQuery: Hashable, Sendable {
    var text = ""
    var category: RecipeCategory?
    var sort: CommunitySort = .newest
    /// Скрытые пользователем авторы.
    var excludedAuthors: [String] = []

    /// Слова запроса в нижнем регистре, «ё» → «е»: так сервер хранит поисковый текст.
    var words: [String] {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .prefix(6)
            .map { $0 }
    }
}

struct CommunityPage<Item: Sendable>: Sendable {
    let items: [Item]
    let hasMore: Bool
}

/// Что автор заполнил в редакторе рецепта.
struct RecipeDraft: Sendable {
    var title = ""
    var summary = ""
    var story = ""
    var category: RecipeCategory = .main
    var country: String?
    var difficulty = 1
    var prepMinutes = 15
    var cookMinutes = 30
    var servings = 2
    var ingredients: [CommunityIngredient] = []
    var steps: [CommunityStep] = []
    var isPublished = true
    /// Фото, которые уже на сервере и остаются.
    var keptPhotos: [CommunityPhoto] = []
    /// Имена файлов на сервере, которые нужно удалить.
    var removedPhotoNames: [String] = []
    /// Новые фото в JPEG.
    var newPhotos: [Data] = []

    static let maxPhotos = 6

    init() {}

    init(recipe: CommunityRecipe) {
        title = recipe.title
        summary = recipe.summary
        story = recipe.story
        category = recipe.category
        country = recipe.country
        difficulty = recipe.difficulty
        prepMinutes = recipe.prepMinutes
        cookMinutes = recipe.cookMinutes
        servings = recipe.servings
        ingredients = recipe.ingredients
        steps = recipe.steps
        isPublished = recipe.isPublished
        keptPhotos = recipe.photos
    }

    /// Черновик без пустых строк и лишних пробелов.
    var cleaned: RecipeDraft {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.story = story.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.ingredients = ingredients.compactMap { item in
            guard let name = item.name.nilIfBlank else { return nil }
            var result = item
            result.name = name
            result.note = item.note?.nilIfBlank
            result.group = item.group?.nilIfBlank
            if result.amount == nil || result.amount == 0 {
                result.amount = nil
                if result.unit != MeasureUnit.toTaste.rawValue { result.unit = nil }
            }
            return result
        }
        copy.steps = steps.compactMap { step in
            guard let text = step.text.nilIfBlank else { return nil }
            return CommunityStep(title: step.title?.nilIfBlank, text: text,
                                 timer: step.timer.flatMap { $0 > 0 ? min($0, 600) : nil })
        }
        return copy
    }

    /// Что нужно исправить перед публикацией; nil — всё в порядке.
    var problem: String? {
        let draft = cleaned
        if draft.title.count < 3 { return "Добавьте название — хотя бы три буквы." }
        if draft.title.count > 120 { return "Название длиннее 120 символов." }
        if draft.ingredients.isEmpty { return "Добавьте хотя бы один ингредиент." }
        if draft.steps.isEmpty { return "Опишите хотя бы один шаг приготовления." }
        if draft.steps.contains(where: { $0.text.count < 3 }) { return "Шаги слишком короткие." }
        if draft.ingredients.count > 60 { return "Не больше 60 ингредиентов." }
        if draft.steps.count > 40 { return "Не больше 40 шагов." }
        return nil
    }
}

/// Отзыв, который пользователь пишет или правит.
struct ReviewDraft: Sendable {
    var rating = 0
    var comment = ""
    /// Новое фото в JPEG.
    var newPhoto: Data?
    /// Удалить фото, которое уже было у отзыва.
    var removesPhoto = false
}

enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam, offensive, wrong, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: "Спам или реклама"
        case .offensive: "Оскорбления или неприемлемое фото"
        case .wrong: "Опасный или ошибочный рецепт"
        case .other: "Другое"
        }
    }
}

enum ReportTarget: Hashable, Sendable, Identifiable {
    case recipe(String)
    case review(String)

    var id: String {
        switch self {
        case .recipe(let id): "recipe-\(id)"
        case .review(let id): "review-\(id)"
        }
    }
}

/// Понятные пользователю ошибки сообщества.
enum CommunityError: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case sessionExpired
    case network
    case rateLimited
    case notFound
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Сервер сообщества не подключён."
        case .notSignedIn: "Войдите в аккаунт сообщества."
        case .sessionExpired: "Сеанс истёк — войдите снова."
        case .network: "Нет связи с сервером сообщества. Проверьте интернет и попробуйте ещё раз."
        case .rateLimited: "Слишком много запросов подряд. Подождите минуту."
        case .notFound: "Рецепт или отзыв не найден — возможно, его удалили."
        case .server(let message): message
        }
    }
}

extension Recipe {
    static let communityPrefix = "community:"

    /// Рецепт-заглушка только ради генеративной обложки.
    static func artworkPlaceholder(id: String, palette: [String]) -> Recipe {
        Recipe(id: id, title: "", subtitle: nil, summary: "", story: "", collections: [], chef: nil, country: nil,
               origin: nil, year: nil, yearLabel: nil, category: .main, difficulty: 1, prepMinutes: 0, cookMinutes: 0,
               restMinutes: 0, servings: 1, calories: nil, diets: [], palette: palette, image: nil, ingredients: [],
               steps: [], plating: nil, pairing: nil, tips: [], source: nil)
    }

    /// Идентификатор рецепта сообщества, если рецепт оттуда.
    var communityID: String? {
        id.hasPrefix(Self.communityPrefix) ? String(id.dropFirst(Self.communityPrefix.count)) : nil
    }

    /// Куда отправлять отзыв об этом рецепте.
    var reviewTarget: ReviewTarget {
        communityID.map(ReviewTarget.community) ?? .catalog(id)
    }
}

extension CommunityRecipe {
    /// Палитра обложки, если автор не добавил фото.
    var palette: [String] {
        let palettes = [
            ["#E9B949", "#F6E7C8", "#C8243B"], ["#5E7F37", "#E8DDC4", "#B4532A"],
            ["#8E2347", "#F1D6C8", "#3A5A40"], ["#2F4858", "#F6AE2D", "#F26419"],
            ["#B4532A", "#F3E3B5", "#5C3D2E"], ["#3D5A80", "#E0FBFC", "#EE6C4D"]
        ]
        return palettes[Int(DailyPick.stableHash(id) % UInt64(palettes.count))]
    }

    /// Рецепт в формате каталога: так работают режим готовки, пересчёт порций и список покупок.
    func asRecipe(catalog: Catalog) -> Recipe {
        Recipe(id: Recipe.communityPrefix + id,
               title: title,
               subtitle: nil,
               summary: summary,
               story: story,
               collections: [],
               chef: nil,
               country: country,
               origin: "Рецепт сообщества · \(author.name)",
               year: nil,
               yearLabel: nil,
               category: category,
               difficulty: difficulty,
               prepMinutes: prepMinutes,
               cookMinutes: cookMinutes,
               restMinutes: 0,
               servings: max(1, servings),
               calories: nil,
               diets: [],
               palette: palette,
               image: nil,
               ingredients: ingredients.map { item in
                   Ingredient(name: item.name, amount: item.amount, unit: item.unit,
                              key: catalog.pantryKey(matching: item.name), note: item.note, group: item.group)
               },
               steps: steps.map { RecipeStep(title: $0.title, text: $0.text, timer: $0.timer.map(Double.init)) },
               plating: nil,
               pairing: nil,
               tips: [],
               source: nil)
    }
}
