import XCTest
@testable import Deshielo

/// Винная и чайная карта: загрузка, ссылки внутри справочника и поиск.
final class DrinkCatalogTests: XCTestCase {
    private var catalog: Catalog!
    private var drinks: DrinkCatalog!

    override func setUpWithError() throws {
        catalog = try CatalogLoader.load(from: .main)
        drinks = try DrinkCatalog.load(from: .main)
    }

    func testDrinksLoadFromBundle() {
        XCTAssertGreaterThanOrEqual(drinks.wine.styles.count, 10)
        XCTAssertGreaterThanOrEqual(drinks.wine.grapes.count, 20)
        XCTAssertGreaterThanOrEqual(drinks.wine.regions.count, 20)
        XCTAssertEqual(drinks.tea.types.count, 7)
        XCTAssertGreaterThanOrEqual(drinks.tea.teas.count, 25)
    }

    func testReferencesAreValid() {
        for grape in drinks.wine.grapes {
            XCTAssertEqual(drinks.styles(of: grape).count, grape.styles.count, grape.id)
            XCTAssertEqual(drinks.regions(of: grape).count, grape.regions.count, grape.id)
            for region in drinks.regions(of: grape) {
                XCTAssertTrue(region.grapes.contains(grape.id), "\(grape.id) ↔ \(region.id)")
            }
            XCTAssertEqual(grape.palette.count, 3, grape.id)
        }
        for region in drinks.wine.regions {
            XCTAssertEqual(drinks.grapes(of: region).count, region.grapes.count, region.id)
        }
        for tea in drinks.tea.teas {
            XCTAssertNotNil(drinks.teaType(tea.type), tea.id)
            if let recipe = tea.recipe {
                XCTAssertNotNil(catalog.recipe(recipe), tea.id)
            }
        }
        let rules = drinks.wine.styles.map(\.pairing) + drinks.tea.teas.map(\.pairing)
        for rule in rules {
            for key in rule.keys + rule.avoid {
                XCTAssertNotNil(catalog.pantryItem(key), "продукт \(key)")
            }
            for term in rule.techniques {
                XCTAssertNotNil(catalog.term(term), "техника \(term)")
            }
        }
        XCTAssertNotNil(drinks.style(drinks.wine.fallback["sweets"]))
        for id in drinks.tea.fallback.values {
            XCTAssertNotNil(drinks.tea(id), id)
        }
    }

    func testSearchFindsGrapesRegionsAndTeas() {
        XCTAssertTrue(drinks.search("пино").grapes.contains { $0.id == "pinot-noir" })
        XCTAssertTrue(drinks.search("Бордо").regions.contains { $0.id == "bordeaux" })
        XCTAssertTrue(drinks.search("улун").teaTypes.contains { $0.id == "oolong" })
        XCTAssertTrue(drinks.search("каштан").teas.contains { $0.id == "longjing" })
        XCTAssertTrue(drinks.search("пино", includesWine: false).grapes.isEmpty, "без вина сорта не ищутся")
        XCTAssertTrue(drinks.search("   ").isEmpty)
    }

    func testBrewingTexts() {
        XCTAssertEqual(TeaBrewing.steepText(30), "30 с")
        XCTAssertEqual(TeaBrewing.steepText(120), "2 мин")
        XCTAssertEqual(TeaBrewing.steepText(90), "1 мин 30 с")
        let brewing = TeaBrewing(temperature: 85, grams: 2.5, water: 150, steeps: [30], note: nil)
        XCTAssertEqual(brewing.ratioText, "2,5 г на 150 мл")
    }

    func testWineSwitch() {
        XCTAssertEqual(DrinksConfig.parse("NO"), false)
        XCTAssertEqual(DrinksConfig.parse("YES"), true)
        XCTAssertNil(DrinksConfig.parse("$(SHOW_WINE)"), "переменная сборки не подставилась — значит, по умолчанию")
        XCTAssertNil(DrinksConfig.parse(""))
    }
}

/// Подбор вина и чая к рецептам.
final class DrinkPairingTests: XCTestCase {
    private var pairings: DrinkPairings!

    override func setUpWithError() throws {
        pairings = DrinkPairings(catalog: try CatalogLoader.load(from: .main), drinks: try DrinkCatalog.load(from: .main))
    }

    private func recipe(_ id: String) throws -> Recipe {
        try XCTUnwrap(pairings.catalog.recipe(id), id)
    }

    private func wine(_ id: String) throws -> String? {
        pairings.wine(for: try recipe(id))?.id
    }

    private func tea(_ id: String) throws -> String? {
        pairings.tea(for: try recipe(id))?.id
    }

    func testClassicWinePairings() throws {
        XCTAssertEqual(try wine("boeuf-bourguignon"), "red-light", "бургундское к бургундскому")
        XCTAssertEqual(try wine("bife-chimichurri"), "red-rich")
        XCTAssertEqual(try wine("coq-au-vin"), "red-light")
        XCTAssertEqual(try wine("tom-yum"), "aromatic")
        XCTAssertEqual(try wine("risotto-milanese"), "white-rich")
        XCTAssertEqual(try wine("pesto-genovese"), "white-light")
        XCTAssertEqual(try wine("ratatouille"), "rose")
        XCTAssertEqual(try wine("pkhali"), "orange")
        XCTAssertEqual(try wine("amatriciana"), "red-medium")
        XCTAssertEqual(try wine("tiramisu"), "fortified")
    }

    func testMatchedIngredientsExplainTheChoice() throws {
        let pick = try XCTUnwrap(pairings.wine(for: try recipe("boeuf-bourguignon")))
        XCTAssertTrue(pick.matched.contains("red-wine"))
        XCTAssertTrue(pairings.ingredientNames(pick).contains("красное сухое вино"))
    }

    func testSweetDishesGetOnlyDessertWines() throws {
        for recipe in pairings.catalog.recipes {
            guard let pick = pairings.wine(for: recipe), let style = pairings.drinks.style(pick.id) else { continue }
            XCTAssertEqual(style.pairing.sweets, DrinkPairing.isSweet(recipe), recipe.id)
        }
        XCTAssertTrue(DrinkPairing.isSweet(try recipe("kulich")))
        XCTAssertFalse(DrinkPairing.isSweet(try recipe("puck-smoked-salmon-pizza")),
                       "чайная ложка мёда в тесте не делает пиццу сладкой")
        let fallback = try XCTUnwrap(pairings.wine(for: try recipe("baklava")))
        XCTAssertEqual(fallback.id, "sweet")
        XCTAssertTrue(fallback.isFallback)
    }

    func testNoWineForBreakfastsAndDrinks() throws {
        XCTAssertNil(try wine("syrniki"))
        XCTAssertNil(try wine("mors"))
        XCTAssertNil(try tea("mors"))
        XCTAssertEqual(try tea("syrniki"), "krasnodar")
    }

    func testLocalTeaWinsTies() throws {
        XCTAssertEqual(try tea("borscht"), "krasnodar")
        XCTAssertEqual(try tea("miso-soup"), "sencha")
        XCTAssertEqual(try tea("baklava"), "rize")
    }

    func testReverseListsStartWithBestMatches() throws {
        let style = try XCTUnwrap(pairings.drinks.style("red-rich"))
        let recipes = pairings.recipes(forStyle: style)
        XCTAssertFalse(recipes.isEmpty)
        XCTAssertEqual(pairings.wine(for: try XCTUnwrap(recipes.first))?.id, "red-rich")
        for recipe in recipes {
            XCTAssertFalse(DrinkPairing.isSweet(recipe), "\(recipe.id): к полнотелому красному — не десерт")
        }
        let assam = try XCTUnwrap(pairings.drinks.tea("assam"))
        XCTAssertTrue(pairings.recipes(forTea: assam).contains { $0.id == "butter-chicken" })
        let chardonnay = try XCTUnwrap(pairings.drinks.grape("chardonnay"))
        XCTAssertFalse(pairings.recipes(forGrape: chardonnay).isEmpty)
    }

    func testRecipeOutsideCatalogIsPairedOnTheFly() throws {
        let recipe = Recipe(id: Recipe.communityPrefix + "test", title: "Говядина в бульоне", subtitle: nil, summary: "",
                            story: "", collections: [], chef: nil, country: nil, origin: nil, year: nil, yearLabel: nil,
                            category: .main, difficulty: 1, prepMinutes: 0, cookMinutes: 0, restMinutes: 0, servings: 4,
                            calories: nil, diets: [], palette: [], image: nil,
                            ingredients: [Ingredient(name: "Говядина", amount: 1, unit: "kg", key: "beef"),
                                          Ingredient(name: "Говяжий бульон", amount: 500, unit: "ml", key: "beef-stock")],
                            steps: [], plating: nil, pairing: nil, tips: [], source: nil)
        XCTAssertEqual(pairings.wine(for: recipe)?.id, "red-rich")
    }
}

/// Распознанный текст этикетки, ссылки на Vivino и дегустационный дневник.
final class TastingTests: XCTestCase {
    func testLabelParserPicksLargestLinesAndVintage() {
        let lines = [
            LabelTextParser.Line(text: "CHÂTEAU EXEMPLE", height: 0.12),
            LabelTextParser.Line(text: "Grand Vin de Bordeaux", height: 0.05),
            LabelTextParser.Line(text: "2016", height: 0.06),
            LabelTextParser.Line(text: "750 ml", height: 0.03),
            LabelTextParser.Line(text: "13,5% vol", height: 0.03),
            LabelTextParser.Line(text: "Contains sulfites", height: 0.02),
            LabelTextParser.Line(text: "Mis en bouteille au château", height: 0.02)
        ]
        let result = LabelTextParser.parse(lines, currentYear: 2026)
        XCTAssertEqual(result.vintage, 2016)
        XCTAssertEqual(result.suggestions, ["Château Exemple", "Grand Vin de Bordeaux"])
        XCTAssertEqual(result.query, "Château Exemple Grand Vin de Bordeaux")
    }

    func testLabelParserSkipsNoiseAndFutureYears() {
        let result = LabelTextParser.parse([
            LabelTextParser.Line(text: "www.example.com", height: 0.2),
            LabelTextParser.Line(text: "4607001234567", height: 0.1),
            LabelTextParser.Line(text: "Урожай 2031", height: 0.05),
            LabelTextParser.Line(text: "Крепость 12% об.", height: 0.04)
        ], currentYear: 2026)
        XCTAssertNil(result.vintage)
        XCTAssertEqual(result.suggestions, ["Урожай"])
    }

    func testVivinoSearchEncodesQuery() throws {
        let url = try XCTUnwrap(VivinoLink.search("Château Margaux & Co 2015"))
        XCTAssertEqual(url.host, "www.vivino.com")
        XCTAssertEqual(url.path, "/search/wines")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.count, 1)
        XCTAssertEqual(components.queryItems?.first?.value, "Château Margaux & Co 2015")
        XCTAssertNil(VivinoLink.search("   "))
    }

    func testTastingRoundTrip() throws {
        let tasting = Tasting(kind: .wine, name: "Красностоп", date: Date(timeIntervalSince1970: 1_700_000_000),
                              vintage: 2021, grapeID: "krasnostop", rating: 5, aromas: ["вишня"])
        let data = try JSONFile<[Tasting]>.makeEncoder().encode([tasting])
        let decoded = try JSONFile<[Tasting]>.makeDecoder().decode([Tasting].self, from: data)
        XCTAssertEqual(decoded, [tasting])
        XCTAssertEqual(decoded.first?.displayName, "Красностоп 2021")

        // Старая запись без необязательных полей тоже читается.
        let minimal = Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"tea","name":"Лунцзин"}"#.utf8)
        let old = try JSONFile<Tasting>.makeDecoder().decode(Tasting.self, from: minimal)
        XCTAssertEqual(old.kind, .tea)
        XCTAssertTrue(old.aromas.isEmpty)
    }

    func testDrinkLinksRoundTrip() {
        let links: [DeepLink] = [.drinks, .tea("longjing"), .grape("saperavi"), .wineRegion("kakheti"),
                                 .wineStyle("orange"), .tastings]
        for link in links {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
    }

    @MainActor
    func testTeaTimerLinkOpensTeaPage() {
        let router = Router()
        router.open(.recipe(Tea.timerPrefix + "longjing"))
        XCTAssertEqual(router.tab, .explore)
        XCTAssertEqual(router.explorePath, [.drinks, .tea("longjing")])
    }
}
