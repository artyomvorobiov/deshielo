import Foundation
import SwiftUI

/// Винная и чайная карта: стили вина, сорта, регионы, типы чая и сами чаи.
/// Загружается из Shared/Content/wine.json и tea.json, как и каталог рецептов.
struct DrinkCatalog: Sendable {
    let wine: WineBook
    let tea: TeaBook

    private let stylesByID: [String: WineStyle]
    private let grapesByID: [String: Grape]
    private let regionsByID: [String: WineRegion]
    private let typesByID: [String: TeaType]
    private let teasByID: [String: Tea]

    init(wine: WineBook, tea: TeaBook) {
        self.wine = wine
        self.tea = tea
        stylesByID = Dictionary(wine.styles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        grapesByID = Dictionary(wine.grapes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        regionsByID = Dictionary(wine.regions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        typesByID = Dictionary(tea.types.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        teasByID = Dictionary(tea.teas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static let empty = DrinkCatalog(wine: .empty, tea: .empty)

    static let bundled: DrinkCatalog = {
        do {
            return try load(from: .main)
        } catch {
            print("Deshielo: не удалось загрузить винную и чайную карту — \(error)")
            return .empty
        }
    }()

    static func load(from bundle: Bundle) throws -> DrinkCatalog {
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw CatalogError.missingFile(name)
            }
            return try decoder.decode(T.self, from: Data(contentsOf: url))
        }
        return DrinkCatalog(wine: try decode(WineBook.self, "wine"), tea: try decode(TeaBook.self, "tea"))
    }

    // MARK: - Поиск по идентификаторам

    func style(_ id: String?) -> WineStyle? { id.flatMap { stylesByID[$0] } }
    func grape(_ id: String?) -> Grape? { id.flatMap { grapesByID[$0] } }
    func region(_ id: String?) -> WineRegion? { id.flatMap { regionsByID[$0] } }
    func teaType(_ id: String?) -> TeaType? { id.flatMap { typesByID[$0] } }
    func tea(_ id: String?) -> Tea? { id.flatMap { teasByID[$0] } }

    // MARK: - Связи

    func grapes(inStyle id: String) -> [Grape] { wine.grapes.filter { $0.styles.contains(id) } }
    func styles(of grape: Grape) -> [WineStyle] { grape.styles.compactMap { style($0) } }
    func regions(of grape: Grape) -> [WineRegion] { grape.regions.compactMap { region($0) } }
    func grapes(of region: WineRegion) -> [Grape] { region.grapes.compactMap { grape($0) } }
    func teas(ofType id: String) -> [Tea] { tea.teas.filter { $0.type == id } }

    /// Красные и белые сорта отдельно — для списка сортов.
    func grapes(_ color: WineColor) -> [Grape] { wine.grapes.filter { $0.color == color } }

    // MARK: - Поиск

    struct SearchResults: Sendable {
        var styles: [WineStyle] = []
        var grapes: [Grape] = []
        var regions: [WineRegion] = []
        var teaTypes: [TeaType] = []
        var teas: [Tea] = []

        var isEmpty: Bool {
            styles.isEmpty && grapes.isEmpty && regions.isEmpty && teaTypes.isEmpty && teas.isEmpty
        }
    }

    /// Поиск по названиям, оригинальным названиям, ароматам и описаниям.
    /// Каждое слово запроса должно где-то встретиться.
    func search(_ query: String, includesWine: Bool = true) -> SearchResults {
        let tokens = query.searchNormalized
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
        guard !tokens.isEmpty else { return SearchResults() }
        func matches(_ fields: [String]) -> Bool {
            let text = fields.joined(separator: " ").searchNormalized
            return tokens.allSatisfy { text.contains($0) }
        }
        var results = SearchResults()
        if includesWine {
            results.styles = wine.styles.filter { matches([$0.name, $0.summary]) }
            results.grapes = wine.grapes.filter { matches([$0.name, $0.original, $0.summary] + $0.aromas) }
            results.regions = wine.regions.filter { region in
                matches([region.name, region.original, region.summary,
                         Locale(identifier: "ru_RU").localizedString(forRegionCode: region.country) ?? ""])
            }
        }
        results.teaTypes = tea.types.filter { matches([$0.name, $0.summary]) }
        results.teas = tea.teas.filter { matches([$0.name, $0.original, $0.origin, $0.summary] + $0.aromas) }
        return results
    }
}

/// Включена ли винная часть раздела. Выключается в Config/Shared.xcconfig (SHOW_WINE = NO) —
/// тогда остаётся чайная карта, а возрастной рейтинг приложения не повышается.
enum DrinksConfig {
    static var showsWine: Bool {
        // Аргумент запуска `-ShowsWine NO` — для проверки варианта без вина.
        if let override = parse(UserDefaults.standard.string(forKey: "ShowsWine")) {
            return override
        }
        return parse(Bundle.main.object(forInfoDictionaryKey: "ShowsWine") as? String) ?? true
    }

    static func parse(_ value: String?) -> Bool? {
        guard let value = value?.nilIfBlank, !value.contains("$(") else { return nil }
        switch value.lowercased() {
        case "no", "false", "0": return false
        case "yes", "true", "1": return true
        default: return nil
        }
    }
}

private struct DrinksKey: EnvironmentKey {
    static let defaultValue = DrinkCatalog.bundled
}

extension EnvironmentValues {
    /// Винная и чайная карта. По умолчанию — загруженная из бандла.
    var drinks: DrinkCatalog {
        get { self[DrinksKey.self] }
        set { self[DrinksKey.self] = newValue }
    }
}
