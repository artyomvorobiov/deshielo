import XCTest
@testable import Deshielo

/// Проверки контента: всё ли загружается и все ли ссылки внутри каталога корректны.
final class CatalogTests: XCTestCase {
    private var catalog: Catalog!

    override func setUpWithError() throws {
        catalog = try CatalogLoader.load(from: .main)
    }

    func testCatalogLoadsFromBundle() {
        XCTAssertGreaterThanOrEqual(catalog.recipes.count, 50)
        XCTAssertFalse(catalog.collections.isEmpty)
        XCTAssertFalse(catalog.glossary.isEmpty)
        XCTAssertFalse(catalog.delivery.isEmpty)
        XCTAssertEqual(catalog.seasons.count, 12)
    }

    func testRecipeIdentifiersAreUnique() {
        let ids = catalog.recipes.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEveryRecipeHasIngredientsAndSteps() {
        for recipe in catalog.recipes {
            XCTAssertFalse(recipe.ingredients.isEmpty, recipe.id)
            XCTAssertFalse(recipe.steps.isEmpty, recipe.id)
            XCTAssertEqual(recipe.palette.count, 3, recipe.id)
            XCTAssertGreaterThan(recipe.servings, 0, recipe.id)
        }
    }

    func testReferencesAreValid() {
        for recipe in catalog.recipes {
            if let chef = recipe.chef {
                XCTAssertNotNil(catalog.chef(chef), "\(recipe.id): шеф \(chef)")
            }
            if let country = recipe.country {
                XCTAssertNotNil(catalog.country(country), "\(recipe.id): страна \(country)")
            }
            for collection in recipe.collections {
                XCTAssertNotNil(catalog.collection(collection), "\(recipe.id): коллекция \(collection)")
            }
            for ingredient in recipe.ingredients {
                if let key = ingredient.key {
                    XCTAssertNotNil(catalog.pantryItem(key), "\(recipe.id): продукт \(key)")
                }
                if let unit = ingredient.unit {
                    XCTAssertNotNil(MeasureUnit(rawValue: unit), "\(recipe.id): единица \(unit)")
                }
            }
            for step in recipe.steps {
                for technique in step.techniques {
                    XCTAssertNotNil(catalog.term(technique), "\(recipe.id): техника \(technique)")
                }
            }
            if let year = recipe.year {
                XCTAssertNotNil(catalog.era(for: year), "\(recipe.id): эпоха для \(year)")
            }
        }
    }

    func testSearchFindsByTitleChefAndIngredient() {
        XCTAssertEqual(catalog.search("пюре").first?.id, "robuchon-puree")
        XCTAssertTrue(catalog.search("Бокюз").contains { $0.id == "soupe-vge" })
        XCTAssertTrue(catalog.search("судак").contains { $0.id == "zander-beurre-blanc" })
        XCTAssertTrue(catalog.search("несуществующееблюдо").isEmpty)
        XCTAssertEqual(catalog.search("").count, catalog.recipes.count)
    }

    func testDailyPickIsStableWithinADay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 8)) ?? .now
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 22)) ?? .now
        let first = DailyPick.recipe(for: morning, in: catalog, calendar: calendar)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, DailyPick.recipe(for: evening, in: catalog, calendar: calendar))
    }

    func testDailyPickCyclesThroughAllRecipes() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now
        var seen = Set<String>()
        for offset in 0..<catalog.recipes.count {
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            if let recipe = DailyPick.recipe(for: day, in: catalog, calendar: calendar) {
                seen.insert(recipe.id)
            }
        }
        XCTAssertEqual(seen.count, catalog.recipes.count)
    }

    func testHistoryCollectionIsChronological() {
        let years = catalog.recipes(inCollection: "history").compactMap(\.year)
        XCTAssertEqual(years, years.sorted())
    }

    func testDeliveryURLsAreBuilt() {
        for service in catalog.delivery {
            let url = service.url(for: "сливочное масло & сыр")
            XCTAssertEqual(url.scheme, "https", service.id)
        }
    }
}
