import Foundation

struct RecipeCollection: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let description: String
    let symbol: String
    let palette: [String]
    /// "countries" — коллекция показывает страны, а не список рецептов.
    let kind: String?

    var showsCountries: Bool { kind == "countries" }
}

struct Chef: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let years: String
    let country: String?
    let role: String
    let bio: String

    /// Инициалы для монограммы.
    var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        return words.prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }
}

struct Country: Codable, Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let cuisine: String
    let lat: Double
    let lon: Double

    var id: String { code }

    /// Эмодзи-флаг из ISO-кода страны.
    var flag: String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

struct Era: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let range: String
    let fromYear: Int
    let toYear: Int
    let description: String

    func contains(_ year: Int) -> Bool { (fromYear...toYear).contains(year) }
}

struct GlossaryTerm: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let term: String
    let definition: String
    let tip: String?
}

struct FoodFact: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let recipe: String?
}

struct SeasonMonth: Codable, Hashable, Sendable {
    let month: Int
    let note: String
    let keys: [String]
}

struct DeliveryService: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case groceries, restaurants, places
    }

    let id: String
    let name: String
    let kind: Kind
    let color: String
    let homeURL: URL
    /// Шаблон поиска с подстановкой {query}. Если его нет, открывается главная страница сервиса.
    let searchURL: String?
    let note: String?

    func url(for query: String?) -> URL {
        guard let query, !query.isEmpty, let template = searchURL,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed),
              let url = URL(string: template.replacingOccurrences(of: "{query}", with: encoded))
        else { return homeURL }
        return url
    }
}

extension CharacterSet {
    /// Символы, допустимые в значении параметра URL (без &, =, + и ?).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#/")
        return set
    }()
}

/// Продукт из pantry.json: название, отдел магазина и эмодзи.
struct PantryItem: Codable, Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let category: Aisle
    let emoji: String
    /// Базовый продукт (соль, перец, масло, вода), который обычно есть дома.
    let staple: Bool
    /// Показывать ли продукт в поиске «Из холодильника».
    let fridge: Bool

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, name, category, emoji, staple, fridge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(Aisle.self, forKey: .category) ?? .other
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "•"
        staple = try c.decodeIfPresent(Bool.self, forKey: .staple) ?? false
        fridge = try c.decodeIfPresent(Bool.self, forKey: .fridge) ?? true
    }
}

/// Отдел магазина — по нему группируется список покупок.
enum Aisle: String, Codable, CaseIterable, Identifiable, Sendable {
    case vegetables, fruits, meat, fish, dairy, bakery, grocery, spices, drinks, frozen, other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Aisle(rawValue: raw) ?? .other
    }

    var title: String {
        switch self {
        case .vegetables: "Овощи и зелень"
        case .fruits: "Фрукты и ягоды"
        case .meat: "Мясо и птица"
        case .fish: "Рыба и морепродукты"
        case .dairy: "Молочное и яйца"
        case .bakery: "Хлеб и выпечка"
        case .grocery: "Бакалея"
        case .spices: "Специи, масла и соусы"
        case .drinks: "Напитки"
        case .frozen: "Заморозка"
        case .other: "Другое"
        }
    }

    var emoji: String {
        switch self {
        case .vegetables: "🥬"
        case .fruits: "🍎"
        case .meat: "🥩"
        case .fish: "🐟"
        case .dairy: "🥛"
        case .bakery: "🥖"
        case .grocery: "🌾"
        case .spices: "🧂"
        case .drinks: "🍷"
        case .frozen: "❄️"
        case .other: "🛒"
        }
    }
}

struct MeasuresBook: Codable, Hashable, Sendable {
    struct Volume: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let detail: String
        let ml: Double
    }

    struct Product: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        /// Граммы в миллилитре.
        let density: Double
    }

    struct Historic: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let origin: String
        /// "mass" — значение в граммах, "volume" — в миллилитрах.
        let kind: String
        let value: Double

        var isMass: Bool { kind == "mass" }
    }

    struct OvenMark: Codable, Hashable, Sendable {
        let gas: Int
        let celsius: Int

        var fahrenheit: Int { Int((Double(celsius) * 9 / 5 + 32).rounded()) }
    }

    let volumes: [Volume]
    let products: [Product]
    let historic: [Historic]
    let ovenMarks: [OvenMark]

    static let empty = MeasuresBook(volumes: [], products: [], historic: [], ovenMarks: [])
}
