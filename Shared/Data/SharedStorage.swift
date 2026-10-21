import Foundation

/// Общая папка приложения и виджетов (App Group).
/// Идентификатор группы берётся из Info.plist (ключ AppGroupIdentifier), который
/// заполняется из Config/Shared.xcconfig. Если группа недоступна (например, не настроена подпись),
/// данные хранятся в папке приложения — всё работает, но виджеты не видят список покупок.
enum AppGroup {
    static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    static var sharedContainerURL: URL? {
        identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    static var isAvailable: Bool { sharedContainerURL != nil }

    static var containerURL: URL {
        if let url = sharedContainerURL { return url }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return support ?? FileManager.default.temporaryDirectory
    }

    static func fileURL(_ name: String) -> URL {
        containerURL.appendingPathComponent(name, isDirectory: false)
    }
}

/// Чтение и запись JSON-файла с координацией доступа: файл могут менять и приложение, и виджет.
struct JSONFile<Value: Codable> {
    let url: URL

    func read() -> Value? {
        var result: Value?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            guard let data = try? Data(contentsOf: readURL) else { return }
            result = try? JSONFile.makeDecoder().decode(Value.self, from: data)
        }
        return result
    }

    func write(_ value: Value) {
        guard let data = try? JSONFile.makeEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
            try? data.write(to: writeURL, options: .atomic)
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Список покупок

struct ShoppingItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var amount: Double?
    var unit: String?
    var key: String?
    var aisle: Aisle
    var recipeIDs: [String]
    var isChecked: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, amount: Double? = nil, unit: String? = nil, key: String? = nil,
         aisle: Aisle = .other, recipeIDs: [String] = [], isChecked: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
        self.key = key
        self.aisle = aisle
        self.recipeIDs = recipeIDs
        self.isChecked = isChecked
        self.createdAt = createdAt
    }

    /// «250 г», «2 зубчика», «по вкусу» или пустая строка.
    var amountText: String { AmountFormatter.format(amount: amount, unit: unit) }
}

struct ShoppingList: Codable, Sendable {
    var items: [ShoppingItem] = []

    var unchecked: [ShoppingItem] { items.filter { !$0.isChecked } }
}

enum ShoppingListStorage {
    static var file: JSONFile<ShoppingList> { JSONFile(url: AppGroup.fileURL("shopping-list.json")) }

    static func load() -> ShoppingList { file.read() ?? ShoppingList() }

    static func save(_ list: ShoppingList) { file.write(list) }

    /// Отметить продукт купленным или вернуть в список. Используется интерактивным виджетом.
    static func toggle(itemID: String) {
        var list = load()
        guard let index = list.items.firstIndex(where: { $0.id.uuidString == itemID }) else { return }
        list.items[index].isChecked.toggle()
        save(list)
    }
}

// MARK: - Профиль: избранное, дневник, заметки, меню, настройки

struct CookedEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var recipeID: String
    var date: Date
    var rating: Int?
    var note: String?

    init(id: UUID = UUID(), recipeID: String, date: Date = .now, rating: Int? = nil, note: String? = nil) {
        self.id = id
        self.recipeID = recipeID
        self.date = date
        self.rating = rating
        self.note = note
    }
}

struct UserProfile: Codable, Sendable {
    /// Избранное, последние добавленные — первыми.
    var favorites: [String] = []
    var cooked: [CookedEntry] = []
    var notes: [String: String] = [:]
    /// Меню на неделю: «2026-10-21» → идентификаторы рецептов.
    var mealPlan: [String: [String]] = [:]
    /// Продукты, отмеченные в «Из холодильника».
    var pantry: [String] = []
    var recent: [String] = []
    var preferredDeliveryID: String?
    var speakSteps: Bool = false
    var includeStaples: Bool = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case favorites, cooked, notes, mealPlan, pantry, recent, preferredDeliveryID, speakSteps, includeStaples
    }

    // Новые поля можно добавлять без потери старых данных: всё читается с запасными значениями.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = (try? c.decodeIfPresent([String].self, forKey: .favorites)) ?? []
        cooked = (try? c.decodeIfPresent([CookedEntry].self, forKey: .cooked)) ?? []
        notes = (try? c.decodeIfPresent([String: String].self, forKey: .notes)) ?? [:]
        mealPlan = (try? c.decodeIfPresent([String: [String]].self, forKey: .mealPlan)) ?? [:]
        pantry = (try? c.decodeIfPresent([String].self, forKey: .pantry)) ?? []
        recent = (try? c.decodeIfPresent([String].self, forKey: .recent)) ?? []
        preferredDeliveryID = try? c.decodeIfPresent(String.self, forKey: .preferredDeliveryID)
        speakSteps = (try? c.decodeIfPresent(Bool.self, forKey: .speakSteps)) ?? false
        includeStaples = (try? c.decodeIfPresent(Bool.self, forKey: .includeStaples)) ?? false
    }
}

enum ProfileStorage {
    static var file: JSONFile<UserProfile> { JSONFile(url: AppGroup.fileURL("profile.json")) }

    static func load() -> UserProfile { file.read() ?? UserProfile() }

    static func save(_ profile: UserProfile) { file.write(profile) }
}

/// Кулинарный паспорт: страны и эпохи, в которых вы уже «побывали», приготовив блюдо.
struct PassportSummary: Sendable {
    /// Код страны → дата первого приготовленного блюда.
    let stamps: [String: Date]
    let eraIDs: Set<String>
    let dishesCount: Int
    let totalCountries: Int
    let totalEras: Int

    init(profile: UserProfile, catalog: Catalog) {
        var stamps: [String: Date] = [:]
        var eras: Set<String> = []
        var dishes: Set<String> = []
        for entry in profile.cooked {
            guard let recipe = catalog.recipe(entry.recipeID) else { continue }
            dishes.insert(recipe.id)
            if let code = recipe.country {
                stamps[code] = min(stamps[code] ?? entry.date, entry.date)
            }
            if let era = catalog.era(for: recipe.year) {
                eras.insert(era.id)
            }
        }
        self.stamps = stamps
        eraIDs = eras
        dishesCount = dishes.count
        totalCountries = catalog.countriesWithRecipes.count
        totalEras = Set(catalog.datedRecipes.compactMap { catalog.era(for: $0.year)?.id }).count
    }

    var countriesCount: Int { stamps.count }
}
