import UIKit
import XCTest
@testable import Deshielo

final class CommunityClientTests: XCTestCase {
    func testFilterValuesAreQuotedAndEscaped() {
        XCTAssertEqual(PocketBaseFilter.quote("сыр"), "\"сыр\"")
        XCTAssertEqual(PocketBaseFilter.quote("a\"b\\c"), "\"a\\\"b\\\\c\"")
        XCTAssertEqual(PocketBaseFilter.all(["a = 1", "", "b = 2"]), "a = 1 && b = 2")
    }

    func testQueryWordsMatchServerSearchText() {
        let query = CommunityQuery(text: "Ёжики  в ТОМАТЕ,сыр")
        XCTAssertEqual(query.words, ["ежики", "в", "томате", "сыр"])
        XCTAssertEqual(CommunityQuery(text: "   ").words, [])
    }

    func testQueryEncodingKeepsPlusAmpersandAndEquals() throws {
        let client = PocketBaseClient(baseURL: try XCTUnwrap(URL(string: "https://example.com/")))
        let url = client.url("/api/collections/recipes/records", query: [("filter", "search ~ \"a+b&c=d\"")])
        XCTAssertEqual(url.absoluteString,
                       "https://example.com/api/collections/recipes/records?filter=search%20~%20%22a%2Bb%26c%3Dd%22")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first?.value, "search ~ \"a+b&c=d\"")
        XCTAssertEqual(client.fileURL(collectionID: "recipes", recordID: "r1", name: "photo_1.jpg", thumb: "600x0").absoluteString,
                       "https://example.com/api/files/recipes/r1/photo_1.jpg?thumb=600x0")
    }

    func testPocketBaseDates() throws {
        let date = try XCTUnwrap(PocketBaseDate.parse("2026-10-22 20:48:05.123Z"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_792_702_085.123, accuracy: 0.001)
        XCTAssertNotNil(PocketBaseDate.parse("2026-10-22 20:48:05Z"))
        XCTAssertNil(PocketBaseDate.parse(""))
    }

    func testMultipartBody() {
        var form = MultipartForm(boundary: "XYZ")
        form.jsonPayload = Data("{\"rating\":5}".utf8)
        form.addJPEG(field: "photo", data: Data("JPEG".utf8))
        let body = String(decoding: form.encoded(), as: UTF8.self)
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=XYZ")
        XCTAssertEqual(body, """
        --XYZ\r
        Content-Disposition: form-data; name="@jsonPayload"\r
        Content-Type: application/json\r
        \r
        {"rating":5}\r
        --XYZ\r
        Content-Disposition: form-data; name="photo"; filename="photo-1.jpg"\r
        Content-Type: image/jpeg\r
        \r
        JPEG\r
        --XYZ--\r

        """)
    }

    func testServerErrorsBecomeRussianMessages() {
        func error(_ status: Int, _ json: String, _ path: String = "/api/collections/recipes/records") -> CommunityError {
            PocketBaseErrorMapper.error(status: status, body: Data(json.utf8), path: path)
        }
        XCTAssertEqual(error(400, #"{"message":"Failed to create record.","data":{"email":{"code":"validation_not_unique"}}}"#,
                             "/api/collections/users/records"),
                       .server("Эта почта уже зарегистрирована. Войдите или восстановите пароль."))
        XCTAssertEqual(error(400, #"{"message":"Текст нарушает правила сообщества.","data":{}}"#),
                       .server("Текст нарушает правила сообщества."))
        XCTAssertEqual(error(400, #"{"message":"Failed to authenticate.","data":{}}"#,
                             "/api/collections/users/auth-with-password"),
                       .server("Неверная почта или пароль."))
        XCTAssertEqual(error(400, #"{"data":{"author":{"code":"validation_not_unique"},"catalog_id":{"code":"validation_not_unique"}}}"#,
                             "/api/collections/reviews/records"),
                       .server("Вы уже оставили отзыв на этот рецепт."))
        XCTAssertEqual(error(400, #"{"data":{"password":{"code":"validation_min_text_constraint"},"name":{"code":"validation_required"}}}"#,
                             "/api/collections/users/records"),
                       .server("Пароль должен быть не короче 8 символов."))
        XCTAssertEqual(error(400, #"{"data":{"title":{"code":"validation_required"}}}"#), .server("Заполните поле «Название»."))
        XCTAssertEqual(error(401, ""), .sessionExpired)
        XCTAssertEqual(error(404, ""), .notFound)
        XCTAssertEqual(error(429, ""), .rateLimited)
        XCTAssertEqual(error(502, "<html>"), .server("Сервер сообщества временно недоступен. Попробуйте позже."))
    }

    func testDraftIsCleanedBeforeSending() {
        var draft = RecipeDraft()
        draft.title = "  Щи "
        XCTAssertEqual(draft.problem, "Добавьте название — хотя бы три буквы.")
        draft.title = "  Щи суточные "
        draft.ingredients = [CommunityIngredient(name: "  "),
                             CommunityIngredient(name: " Капуста ", amount: 0, unit: "g"),
                             CommunityIngredient(name: "Соль", unit: "toTaste")]
        XCTAssertEqual(draft.problem, "Опишите хотя бы один шаг приготовления.")
        draft.steps = [CommunityStep(text: "  "), CommunityStep(title: " ", text: "Томите в печи всю ночь.", timer: 900)]
        XCTAssertNil(draft.problem)
        let cleaned = draft.cleaned
        XCTAssertEqual(cleaned.title, "Щи суточные")
        XCTAssertEqual(cleaned.ingredients, [CommunityIngredient(name: "Капуста"), CommunityIngredient(name: "Соль", unit: "toTaste")])
        XCTAssertEqual(cleaned.steps, [CommunityStep(text: "Томите в печи всю ночь.", timer: 600)])
    }

    func testEditorRowsConvertAmounts() {
        var row = EditableIngredient()
        row.name = "Мука"
        row.amount = "1,5"
        row.unit = "kg"
        XCTAssertEqual(row.ingredient, CommunityIngredient(name: "Мука", amount: 1.5, unit: "kg"))
        row.amount = ""
        XCTAssertEqual(row.ingredient, CommunityIngredient(name: "Мука"))
        row.unit = "toTaste"
        XCTAssertEqual(row.ingredient, CommunityIngredient(name: "Мука", unit: "toTaste"))
        XCTAssertEqual(EditableIngredient(CommunityIngredient(name: "Сахар", amount: 2.5, unit: "tbsp")).amount, "2,5")
        var step = EditableStep()
        step.text = "Варите"
        step.timer = " 15 "
        XCTAssertEqual(step.step.timer, 15)
        step.timer = "0"
        XCTAssertNil(step.step.timer)
    }

    func testCommunityRecipeWorksAsCatalogRecipe() {
        let catalog = Catalog.bundled
        let recipe = CommunityRecipe(id: "abc", author: CommunityAuthor(id: "u1", name: "Анна"), title: "Сырники",
                                     summary: "", story: "", category: .breakfast, country: "RU", difficulty: 1,
                                     prepMinutes: 10, cookMinutes: 15, servings: 2,
                                     ingredients: [CommunityIngredient(name: "Творога 9%", amount: 400, unit: "g"),
                                                   CommunityIngredient(name: "Яйцо", amount: 1, unit: "pcs"),
                                                   CommunityIngredient(name: "Топинамбур", amount: 1, unit: "pcs"),
                                                   CommunityIngredient(name: "Соль", unit: "toTaste")],
                                     steps: [CommunityStep(title: "Тесто", text: "Смешайте всё.", timer: 5)],
                                     photos: [], isPublished: true, isHidden: false, rating: .empty, created: .now)
        let converted = recipe.asRecipe(catalog: catalog)
        XCTAssertEqual(converted.id, "community:abc")
        XCTAssertEqual(converted.communityID, "abc")
        XCTAssertEqual(converted.reviewTarget, .community("abc"))
        XCTAssertEqual(converted.ingredients.map(\.key), ["tvorog", "egg", nil, "salt"])
        XCTAssertEqual(converted.steps.first?.timer, 5)
        XCTAssertEqual(catalog.recipe("plov")?.reviewTarget, .catalog("plov"))

        let items = ShoppingMerger.items(for: converted, scale: 1, catalog: catalog, includeStaples: false, onlyIndices: nil)
        XCTAssertEqual(items.map(\.name), ["Творог", "Яйца", "Топинамбур"])
        XCTAssertEqual(items.first?.recipeTitle, "Сырники")
    }

    func testCommunityDeepLinks() {
        let link = DeepLink.communityRecipe("k3x9")
        XCTAssertEqual(link.url.absoluteString, "deshielo://community/k3x9")
        XCTAssertEqual(DeepLink(url: link.url), link)
    }

    @MainActor
    func testTimerLinksOfCommunityRecipesOpenCommunityTab() {
        let router = Router()
        router.open(.recipe("community:k3x9"))
        XCTAssertEqual(router.tab, .community)
        XCTAssertEqual(router.communityPath, [.communityRecipe("k3x9")])
        router.searchCommunity("щи")
        XCTAssertEqual(router.communitySearch, "щи")
        XCTAssertEqual(router.communityPath, [])
    }

    func testRatingTextUsesRussianFormat() {
        XCTAssertEqual(RatingText.average(4.66), "4,7")
        XCTAssertEqual(RatingText.summary(RatingSummary(average: 4.5, count: 12)), "4,5 · 12 оценок")
        XCTAssertEqual(RatingText.summary(RatingSummary(average: 5, count: 1)), "5,0 · 1 оценка")
    }

    func testCompressedPhotosAreSmallJPEGs() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let data = try XCTUnwrap(ImageCompressor.jpegData(from: image))
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size, CGSize(width: 1600, height: 1200))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
    }
}

/// Логика сообщества на демо-сервисе: без сети, но с теми же правилами для экрана.
final class CommunityStoreTests: XCTestCase {
    @MainActor
    private func makeStore() -> CommunityStore {
        CommunityStore(service: DemoCommunityService(), session: DemoCommunityService.session, persistsSession: false)
    }

    @MainActor
    func testReviewIsCreatedOnceAndUpdatesRating() async throws {
        let store = makeStore()
        let target = ReviewTarget.community("demo-sharlotka")
        try await store.saveReview(ReviewDraft(rating: 5, comment: "Отлично"), for: target, existingID: nil)
        var recipe = try await store.recipe(id: "demo-sharlotka")
        XCTAssertEqual(recipe.rating, RatingSummary(average: 5, count: 1))
        // Повторный отзыв того же человека обновляет прежний, а не создаёт второй.
        try await store.saveReview(ReviewDraft(rating: 3), for: target, existingID: nil)
        let reviews = try await store.reviews(for: target, page: 1)
        XCTAssertEqual(reviews.items.map(\.rating), [3])
        recipe = try await store.recipe(id: "demo-sharlotka")
        XCTAssertEqual(recipe.rating, RatingSummary(average: 3, count: 1))
        let mine = try await store.myReview(for: target)
        XCTAssertEqual(mine?.id, reviews.items.first?.id)
    }

    @MainActor
    func testSearchAndCategories() async throws {
        let store = makeStore()
        let found = try await store.recipes(CommunityQuery(text: "сырники"), page: 1)
        XCTAssertEqual(found.items.map(\.id), ["demo-syrniki"])
        let baking = try await store.recipes(CommunityQuery(category: .baking), page: 1)
        XCTAssertTrue(baking.items.allSatisfy { $0.category == .baking })
        let all = try await store.recipes(CommunityQuery(), page: 1)
        XCTAssertFalse(all.items.contains { !$0.isPublished }, "Черновики не попадают в ленту")
    }

    @MainActor
    func testBlockedAuthorsDisappear() async throws {
        let store = makeStore()
        let before = try await store.recipes(CommunityQuery(), page: 1)
        let author = try XCTUnwrap(before.items.first { $0.author.id == "demo-olga" }?.author)
        store.block(author)
        let after = try await store.recipes(CommunityQuery(), page: 1)
        let reviews = try await store.reviews(for: .catalog("beef-wellington"), page: 1)
        store.unblock(author.id)
        XCTAssertFalse(after.items.contains { $0.author.id == author.id })
        XCTAssertFalse(reviews.items.contains { $0.author.id == author.id })
        XCTAssertTrue(store.blockedAuthors.isEmpty)
    }

    @MainActor
    func testSignedOutStoreAsksToSignIn() async {
        let store = CommunityStore(service: DemoCommunityService(), session: nil, persistsSession: false)
        do {
            try await store.saveReview(ReviewDraft(rating: 5), for: .catalog("plov"), existingID: nil)
            XCTFail("Без аккаунта отзыв не отправляется")
        } catch {
            XCTAssertEqual(error as? CommunityError, .notSignedIn)
        }
        let unconfigured = CommunityStore(service: nil, persistsSession: false)
        XCTAssertFalse(unconfigured.isConfigured)
        do {
            _ = try await unconfigured.recipes(CommunityQuery(), page: 1)
            XCTFail("Без сервера запросов нет")
        } catch {
            XCTAssertEqual(error as? CommunityError, .notConfigured)
        }
    }
}
