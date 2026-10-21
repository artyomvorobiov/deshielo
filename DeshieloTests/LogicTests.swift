import XCTest
@testable import Deshielo

final class FormattingTests: XCTestCase {
    func testRussianPlural() {
        XCTAssertEqual(RussianPlural.phrase(1, "рецепт", "рецепта", "рецептов"), "1 рецепт")
        XCTAssertEqual(RussianPlural.phrase(3, "рецепт", "рецепта", "рецептов"), "3 рецепта")
        XCTAssertEqual(RussianPlural.phrase(11, "рецепт", "рецепта", "рецептов"), "11 рецептов")
        XCTAssertEqual(RussianPlural.phrase(21, "рецепт", "рецепта", "рецептов"), "21 рецепт")
        XCTAssertEqual(RussianPlural.phrase(112, "рецепт", "рецепта", "рецептов"), "112 рецептов")
        XCTAssertEqual(RussianPlural.form(1.5, "зубчик", "зубчика", "зубчиков"), "зубчика")
    }

    func testAmountFormatting() {
        XCTAssertEqual(AmountFormatter.format(amount: 250, unit: "g"), "250 г")
        XCTAssertEqual(AmountFormatter.format(amount: 1250, unit: "g"), "1,25 кг")
        XCTAssertEqual(AmountFormatter.format(amount: 1.5, unit: "kg"), "1,5 кг")
        XCTAssertEqual(AmountFormatter.format(amount: 0.5, unit: "pcs"), "½ шт.")
        XCTAssertEqual(AmountFormatter.format(amount: 1.5, unit: "clove"), "1½ зубчика")
        XCTAssertEqual(AmountFormatter.format(amount: 5, unit: "clove"), "5 зубчиков")
        XCTAssertEqual(AmountFormatter.format(amount: nil, unit: "toTaste"), "по вкусу")
        XCTAssertEqual(AmountFormatter.format(amount: 333.3, unit: "ml"), "335 мл")
        XCTAssertEqual(AmountFormatter.format(amount: 7.3, unit: "g"), "7,5 г")
    }

    func testDurations() {
        XCTAssertEqual(DurationText.short(minutes: 45), "45 мин")
        XCTAssertEqual(DurationText.short(minutes: 90), "1 ч 30 мин")
        XCTAssertEqual(DurationText.short(minutes: 120), "2 ч")
        XCTAssertEqual(DurationText.short(minutes: 2880), "2 сут.")
        XCTAssertEqual(DurationText.clock(seconds: 65), "1:05")
        XCTAssertEqual(DurationText.timerTitle(minutes: 0.5), "30 секунд")
    }

    func testYearLabels() {
        XCTAssertEqual(YearText.short(-1750), "1750 до н. э.")
        XCTAssertEqual(YearText.short(1390), "1390")
    }
}

final class ShoppingMergerTests: XCTestCase {
    func testSameProductIsMergedAcrossUnits() {
        var list = [ShoppingItem(name: "Сливочное масло", amount: 250, unit: "g", key: "butter", aisle: .dairy)]
        ShoppingMerger.merge([ShoppingItem(name: "Сливочное масло", amount: 1, unit: "kg", key: "butter", aisle: .dairy)],
                             into: &list)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].amount, 1250)
        XCTAssertEqual(list[0].unit, "g")
        XCTAssertEqual(list[0].amountText, "1,25 кг")
    }

    func testIncompatibleUnitsStaySeparate() {
        var list = [ShoppingItem(name: "Яйца", amount: 2, unit: "pcs", key: "egg", aisle: .dairy)]
        ShoppingMerger.merge([ShoppingItem(name: "Яйца", amount: 100, unit: "g", key: "egg", aisle: .dairy)], into: &list)
        XCTAssertEqual(list.count, 2)
    }

    func testCheckedItemsAreNotMerged() {
        var list = [ShoppingItem(name: "Мука", amount: 200, unit: "g", key: "flour", aisle: .grocery, isChecked: true)]
        ShoppingMerger.merge([ShoppingItem(name: "Мука", amount: 100, unit: "g", key: "flour", aisle: .grocery)], into: &list)
        XCTAssertEqual(list.count, 2)
    }

    func testRecipeItemsScaleAndSkipStaples() throws {
        let catalog = try CatalogLoader.load(from: .main)
        let recipe = try XCTUnwrap(catalog.recipe("robuchon-puree"))
        let items = ShoppingMerger.items(for: recipe, scale: 2, catalog: catalog, includeStaples: false, onlyIndices: nil)
        let potato = try XCTUnwrap(items.first { $0.key == "potato" })
        XCTAssertEqual(potato.amount, 2)
        XCTAssertFalse(items.contains { $0.key == "salt" }, "соль — базовый продукт")
        XCTAssertFalse(items.contains { $0.key == "water" })
    }
}

final class LinkAndMatchTests: XCTestCase {
    func testDeepLinksRoundTrip() throws {
        let links: [DeepLink] = [.today, .recipe("tuhu"), .cook("libum"), .recipeOfTheDay, .shopping, .passport]
        for link in links {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
        let foreign = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertNil(DeepLink(url: foreign))
    }

    func testFridgeMatcherPrefersRecipesWithFewerMissing() throws {
        let catalog = try CatalogLoader.load(from: .main)
        let matches = FridgeMatcher.matches(pantry: ["tvorog", "egg", "flour", "vanilla"], catalog: catalog)
        let first = try XCTUnwrap(matches.first)
        XCTAssertTrue(first.missing.isEmpty, "\(first.recipe.id): \(first.missing)")
        XCTAssertTrue(matches.contains { $0.recipe.id == "syrniki" })
    }

    func testPassportCountsCountriesOnce() throws {
        let catalog = try CatalogLoader.load(from: .main)
        var profile = UserProfile()
        profile.cooked = [CookedEntry(recipeID: "syrniki"), CookedEntry(recipeID: "bliny"), CookedEntry(recipeID: "tuhu")]
        let passport = PassportSummary(profile: profile, catalog: catalog)
        XCTAssertEqual(passport.countriesCount, 2)
        XCTAssertEqual(passport.dishesCount, 3)
        XCTAssertTrue(passport.eraIDs.contains("ancient"))
    }
}

final class StepIconTests: XCTestCase {
    private func symbol(_ title: String?, _ text: String) -> String {
        StepIcon.symbol(for: RecipeStep(title: title, text: text))
    }

    func testFirstActionWins() {
        XCTAssertEqual(symbol("Обжарьте вырезку", "Посолите и поперчите. Остудите."), "flame")
        XCTAssertEqual(symbol("Соберите рулет", "Заморозьте на 20 минут."), "hand.raised")
        XCTAssertEqual(symbol("Томите под крышкой", "Соберите рис горкой и накройте."), "hourglass")
        XCTAssertEqual(symbol(nil, "Нарежьте лук и обжарьте до золотистого цвета."), "scissors")
    }

    func testKeysMatchOnlyWordStarts() {
        // «Поставьте» содержит «оставьте», а «натрия» начинается как «натрите».
        XCTAssertEqual(symbol("Поставьте воду", "Вскипятите 3 литра воды."), "drop")
        XCTAssertEqual(symbol(nil, "Добавьте альгинат натрия в воду."), "circle.dotted")
    }

    func testParticiplesAndNegationsAreSkipped() {
        XCTAssertEqual(symbol(nil, "Положите охлаждённые сливки и не перемешивайте. Варите 5 минут."), "drop")
        XCTAssertEqual(symbol(nil, "Добавьте нарезанные овощи и тушите."), "flame")
    }

    func testPlacesCount() {
        XCTAssertEqual(symbol(nil, "Переложите в форму и поставьте в духовку."), "oven")
        XCTAssertEqual(symbol(nil, "Накройте и уберите в холодильник на ночь."), "snowflake")
    }
}
