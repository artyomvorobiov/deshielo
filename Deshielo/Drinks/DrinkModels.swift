import Foundation

/// Правило подбора напитка к блюду. По нему считаются очки: совпавшие продукты рецепта,
/// категория, страна и техники; продукты из `avoid` очки отнимают. Подробности — DrinkPairing.
struct DrinkPairingRule: Codable, Hashable, Sendable {
    let keys: [String]
    let categories: [RecipeCategory]
    let countries: [String]
    let techniques: [String]
    let avoid: [String]
    /// Правило для сладкого: десертов и сладкой выпечки. Остальным блюдам такие напитки не советуются.
    let sweets: Bool
    /// Почему это сочетание работает — показывается в рецепте.
    let note: String

    private enum CodingKeys: String, CodingKey {
        case keys, categories, countries, techniques, avoid, sweets, note
    }

    init(keys: [String] = [], categories: [RecipeCategory] = [], countries: [String] = [],
         techniques: [String] = [], avoid: [String] = [], sweets: Bool = false, note: String) {
        self.keys = keys
        self.categories = categories
        self.countries = countries
        self.techniques = techniques
        self.avoid = avoid
        self.sweets = sweets
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
        let categoryNames = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        categories = categoryNames.compactMap(RecipeCategory.init(rawValue:))
        countries = try c.decodeIfPresent([String].self, forKey: .countries) ?? []
        techniques = try c.decodeIfPresent([String].self, forKey: .techniques) ?? []
        avoid = try c.decodeIfPresent([String].self, forKey: .avoid) ?? []
        sweets = try c.decodeIfPresent(Bool.self, forKey: .sweets) ?? false
        note = try c.decode(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keys, forKey: .keys)
        try c.encode(categories.map(\.rawValue), forKey: .categories)
        try c.encode(countries, forKey: .countries)
        try c.encode(techniques, forKey: .techniques)
        try c.encode(avoid, forKey: .avoid)
        try c.encode(sweets, forKey: .sweets)
        try c.encode(note, forKey: .note)
    }
}

// MARK: - Вино

/// Стиль вина: игристое, лёгкое белое, полнотелое красное и так далее.
struct WineStyle: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let description: String
    /// Температура подачи: «6–8 °C».
    let serving: String
    let glass: String
    let palette: [String]
    let pairing: DrinkPairingRule

    var isSparkling: Bool { id == "sparkling" }
    /// Десертные и креплёные вина наливают в маленькие бокалы.
    var isDessert: Bool { pairing.sweets }
}

enum WineColor: String, Codable, Sendable {
    case red, white

    var title: String {
        switch self {
        case .red: "Красный сорт"
        case .white: "Белый сорт"
        }
    }
}

/// Сорт винограда.
struct Grape: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Название на языке оригинала: Cabernet Sauvignon.
    let original: String
    let color: WineColor
    /// Тело, кислотность и танины — по шкале от 1 до 5.
    let body: Int
    let acidity: Int
    let tannin: Int
    let aromas: [String]
    let summary: String
    let story: String
    let styles: [String]
    let regions: [String]
    /// Запрос для поиска в Vivino.
    let vivino: String
    let palette: [String]
}

/// Винодельческий регион.
struct WineRegion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let original: String
    /// ISO-код страны.
    let country: String
    let lat: Double
    let lon: Double
    let summary: String
    let story: String
    let grapes: [String]
    let vivino: String
}

struct WineBook: Codable, Sendable {
    let styles: [WineStyle]
    let grapes: [Grape]
    let regions: [WineRegion]
    /// Запасные варианты: «sweets» — стиль для сладкого, если ни одно правило не подошло.
    let fallback: [String: String]

    static let empty = WineBook(styles: [], grapes: [], regions: [], fallback: [:])
}

// MARK: - Чай

/// Как заваривать: температура воды, сколько чая на сколько воды и время проливов.
struct TeaBrewing: Codable, Hashable, Sendable {
    let temperature: Int
    let grams: Double
    let water: Int
    /// Время каждого пролива в секундах. Пусто — чай не настаивают (например, матчу взбивают).
    let steeps: [Int]
    let note: String?

    /// «4 г на 150 мл».
    var ratioText: String {
        "\(AmountFormatter.number(grams, fractions: false)) г на \(water) мл"
    }

    /// «30 с», «2 мин», «1 мин 30 с».
    static func steepText(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rest = seconds % 60
        switch (minutes, rest) {
        case (0, _): return "\(seconds) с"
        case (_, 0): return "\(minutes) мин"
        default: return "\(minutes) мин \(rest) с"
        }
    }
}

/// Тип чая: белый, зелёный, улун, чёрный…
struct TeaType: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Степень окисления листа.
    let oxidation: String
    let summary: String
    let description: String
    let palette: [String]
    let brewing: TeaBrewing
}

/// Конкретный чай или травяной настой.
struct Tea: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let original: String
    let type: String
    /// Где растёт: «Ханчжоу, провинция Чжэцзян, Китай».
    let origin: String
    let country: String
    let lat: Double
    let lon: Double
    let aromas: [String]
    let summary: String
    let story: String
    let brewing: TeaBrewing
    let palette: [String]
    let pairing: DrinkPairingRule
    /// Рецепт из каталога с этим чаем (например, масала-чай).
    let recipe: String?

    /// Таймеры заваривания принадлежат «tea:<id>» — так Live Activity открывает страницу чая.
    static let timerPrefix = "tea:"

    var timerOwnerID: String { Self.timerPrefix + id }
}

struct TeaBook: Codable, Sendable {
    let types: [TeaType]
    let teas: [Tea]
    /// Запасные варианты по категории блюда и «sweets» — для сладкого.
    let fallback: [String: String]

    static let empty = TeaBook(types: [], teas: [], fallback: [:])
}

/// Флаг и название страны по ISO-коду, даже если её нет в countries.json (Новая Зеландия, Шри-Ланка…).
enum CountryName {
    static func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }

    static func name(_ code: String, catalog: Catalog) -> String {
        if let country = catalog.country(code) { return country.name }
        return Locale(identifier: "ru_RU").localizedString(forRegionCode: code) ?? code
    }
}
