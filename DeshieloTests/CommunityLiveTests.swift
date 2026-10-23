import UIKit
import XCTest
@testable import Deshielo

/// Клиент сообщества на настоящем сервере PocketBase.
/// В CI сервер запускается перед тестами (TEST_RUNNER_COMMUNITY_TEST_URL), без него тесты пропускаются.
/// Локально: запустите сервер (docs/COMMUNITY.md) и задайте COMMUNITY_TEST_URL в схеме тестов.
final class CommunityLiveTests: XCTestCase {
    private var service: PocketBaseCommunityService!
    private let password = "very-secret-42"

    override func setUpWithError() throws {
        guard let value = ProcessInfo.processInfo.environment["COMMUNITY_TEST_URL"], let url = URL(string: value) else {
            throw XCTSkip("Сервер сообщества не задан (COMMUNITY_TEST_URL)")
        }
        service = PocketBaseCommunityService(baseURL: url)
    }

    func testRecipesReviewsAndAccounts() async throws {
        let run = UUID().uuidString.prefix(8).lowercased()
        let author = try await service.signUp(name: "Анна", email: "anna-\(run)@example.com", password: password)
        let reader = try await service.signUp(name: "Борис", email: "boris-\(run)@example.com", password: password)
        XCTAssertEqual(author.user.name, "Анна")
        XCTAssertEqual(author.user.email, "anna-\(run)@example.com")
        let refreshed = try await service.refresh(author)
        XCTAssertEqual(refreshed.user.id, author.user.id)

        // Рецепт с фото: создание, поиск без учёта регистра, фото с миниатюрой.
        var draft = RecipeDraft()
        draft.title = "Сырники \(run)"
        draft.summary = "Нежные, с изюмом"
        draft.category = .breakfast
        draft.country = "RU"
        draft.ingredients = [CommunityIngredient(name: "Творог", amount: 400, unit: "g"),
                             CommunityIngredient(name: "Соль", unit: "toTaste")]
        draft.steps = [CommunityStep(title: "Тесто", text: "Смешайте творог с яйцом и мукой.", timer: 5)]
        draft.newPhotos = [try XCTUnwrap(Self.photo(.orange))]
        let recipe = try await service.saveRecipe(draft, id: nil, session: author)
        XCTAssertEqual(recipe.author.name, "Анна")
        XCTAssertEqual(recipe.photos.count, 1)
        XCTAssertEqual(recipe.ingredients, draft.ingredients)
        XCTAssertEqual(recipe.steps.first?.timer, 5)
        XCTAssertEqual(recipe.rating, RatingSummary(average: 0, count: 0))

        let (photoData, photoResponse) = try await URLSession.shared.data(from: recipe.photos[0].thumbnailURL)
        XCTAssertEqual((photoResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNotNil(UIImage(data: photoData))

        let found = try await service.recipes(CommunityQuery(text: "СЫРНИКИ \(run)"), page: 1, session: nil)
        XCTAssertEqual(found.items.map(\.id), [recipe.id])
        let best = try await service.recipes(CommunityQuery(category: .breakfast, sort: .best), page: 1, session: nil)
        XCTAssertTrue(best.items.contains { $0.id == recipe.id })
        let hidden = try await service.recipes(CommunityQuery(text: "сырники \(run)", excludedAuthors: [author.user.id]),
                                               page: 1, session: nil)
        XCTAssertTrue(hidden.items.isEmpty, "Скрытый автор не попадает в выдачу")

        // Отзыв с фото и рейтинг.
        let review = try await service.saveReview(ReviewDraft(rating: 4, comment: "Получилось!",
                                                              newPhoto: try XCTUnwrap(Self.photo(.green))),
                                                  for: .community(recipe.id), existingID: nil, session: reader)
        XCTAssertNotNil(review.photo)
        XCTAssertEqual(review.author.name, "Борис")
        var rated = try await service.recipe(id: recipe.id, session: nil)
        XCTAssertEqual(rated.rating, RatingSummary(average: 4, count: 1))

        let updated = try await service.saveReview(ReviewDraft(rating: 2, comment: "Передумал", removesPhoto: true),
                                                   for: .community(recipe.id), existingID: review.id, session: reader)
        XCTAssertNil(updated.photo)
        rated = try await service.recipe(id: recipe.id, session: nil)
        XCTAssertEqual(rated.rating, RatingSummary(average: 2, count: 1))
        let mine = try await service.myReview(for: .community(recipe.id), session: reader)
        XCTAssertEqual(mine?.id, review.id)

        do {
            _ = try await service.saveReview(ReviewDraft(rating: 5), for: .community(recipe.id), existingID: nil, session: author)
            XCTFail("Свой рецепт оценить нельзя")
        } catch let error as CommunityError {
            XCTAssertEqual(error, .server("Нельзя оценивать собственный рецепт."))
        }

        // Отзыв на рецепт каталога и средняя оценка каталога.
        _ = try await service.saveReview(ReviewDraft(rating: 5, comment: "Как в Ташкенте"),
                                         for: .catalog("plov"), existingID: nil, session: reader)
        let ratings = try await service.catalogRatings()
        XCTAssertEqual(ratings["plov"], RatingSummary(average: 5, count: 1))
        let plovReviews = try await service.reviews(for: .catalog("plov"), page: 1, excludedAuthors: [])
        XCTAssertEqual(plovReviews.items.map(\.author.name), ["Борис"])
        let withoutReader = try await service.reviews(for: .catalog("plov"), page: 1, excludedAuthors: [reader.user.id])
        XCTAssertTrue(withoutReader.items.isEmpty)

        try await service.report(.recipe(recipe.id), reason: .spam, comment: "проверка", session: reader)

        // Черновик виден только автору, лишнее фото удаляется.
        var edit = RecipeDraft(recipe: recipe)
        edit.isPublished = false
        edit.removedPhotoNames = recipe.photos.map(\.name)
        edit.keptPhotos = []
        let draftRecipe = try await service.saveRecipe(edit, id: recipe.id, session: author)
        XCTAssertFalse(draftRecipe.isPublished)
        XCTAssertTrue(draftRecipe.photos.isEmpty)
        do {
            _ = try await service.recipe(id: recipe.id, session: reader)
            XCTFail("Чужой черновик не должен открываться")
        } catch let error as CommunityError {
            XCTAssertEqual(error, .notFound)
        }
        let own = try await service.recipes(byAuthor: author.user.id, session: author)
        XCTAssertEqual(own.map(\.id), [recipe.id])

        var rude = RecipeDraft()
        rude.title = "Охуенные сырники"
        rude.ingredients = draft.ingredients
        rude.steps = draft.steps
        do {
            _ = try await service.saveRecipe(rude, id: nil, session: author)
            XCTFail("Грубые слова не публикуются")
        } catch let error as CommunityError {
            XCTAssertTrue(error.localizedDescription.contains("правила"), error.localizedDescription)
        }

        let renamed = try await service.rename("Анна К.", session: author)
        XCTAssertEqual(renamed.name, "Анна К.")

        // Удаление аккаунта уносит его рецепты и отзывы.
        try await service.deleteAccount(reader)
        let afterDeletion = try await service.catalogRatings()
        XCTAssertNil(afterDeletion["plov"].flatMap { $0.count > 0 ? $0 : nil })
        try await service.deleteAccount(author)
        do {
            _ = try await service.signIn(email: "anna-\(run)@example.com", password: password)
            XCTFail("Удалённый аккаунт не входит")
        } catch let error as CommunityError {
            XCTAssertEqual(error, .server("Неверная почта или пароль."))
        }
    }

    func testFriendlyErrors() async throws {
        let run = UUID().uuidString.prefix(8).lowercased()
        let session = try await service.signUp(name: "Вера", email: "vera-\(run)@example.com", password: password)
        do {
            _ = try await service.signUp(name: "Вера", email: "vera-\(run)@example.com", password: password)
            XCTFail("Почта уже занята")
        } catch let error as CommunityError {
            XCTAssertEqual(error, .server("Эта почта уже зарегистрирована. Войдите или восстановите пароль."))
        }
        do {
            _ = try await service.recipe(id: "nosuchrecipe000", session: nil)
            XCTFail("Такого рецепта нет")
        } catch let error as CommunityError {
            XCTAssertEqual(error, .notFound)
        }
        var expired = session
        expired.token = "broken"
        do {
            _ = try await service.refresh(expired)
            XCTFail("Испорченный токен не принимается")
        } catch let error as CommunityError {
            XCTAssertEqual(error, .sessionExpired)
        }
        try await service.deleteAccount(session)
    }

    private static func photo(_ color: UIColor) -> Data? {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        }
        return ImageCompressor.jpegData(from: image)
    }
}
