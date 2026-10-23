import Foundation

/// Операции сообщества. Рабочая реализация ходит в PocketBase,
/// демо-версия хранит всё в памяти — для скриншотов и UI-тестов.
protocol CommunityService: Sendable {
    func signUp(name: String, email: String, password: String) async throws -> CommunitySession
    func signIn(email: String, password: String) async throws -> CommunitySession
    func refresh(_ session: CommunitySession) async throws -> CommunitySession
    func requestPasswordReset(email: String) async throws
    func rename(_ name: String, session: CommunitySession) async throws -> CommunityUser
    func deleteAccount(_ session: CommunitySession) async throws

    func recipes(_ query: CommunityQuery, page: Int, session: CommunitySession?) async throws -> CommunityPage<CommunityRecipe>
    /// Рецепты автора. Свои черновики и скрытые модератором рецепты видны только самому автору.
    func recipes(byAuthor authorID: String, session: CommunitySession?) async throws -> [CommunityRecipe]
    func recipe(id: String, session: CommunitySession?) async throws -> CommunityRecipe
    func saveRecipe(_ draft: RecipeDraft, id: String?, session: CommunitySession) async throws -> CommunityRecipe
    func deleteRecipe(id: String, session: CommunitySession) async throws

    func reviews(for target: ReviewTarget, page: Int, excludedAuthors: [String]) async throws -> CommunityPage<CommunityReview>
    func myReview(for target: ReviewTarget, session: CommunitySession) async throws -> CommunityReview?
    func saveReview(_ draft: ReviewDraft, for target: ReviewTarget, existingID: String?,
                    session: CommunitySession) async throws -> CommunityReview
    func deleteReview(id: String, session: CommunitySession) async throws
    /// Средние оценки рецептов из каталога приложения: id рецепта → рейтинг.
    func catalogRatings() async throws -> [String: RatingSummary]

    func report(_ target: ReportTarget, reason: ReportReason, comment: String, session: CommunitySession) async throws
}

/// Сообщество на сервере PocketBase.
struct PocketBaseCommunityService: CommunityService {
    let client: PocketBaseClient

    static let pageSize = 20

    init(baseURL: URL, urlSession: URLSession = .shared) {
        client = PocketBaseClient(baseURL: baseURL, urlSession: urlSession)
    }

    // MARK: - Аккаунт

    func signUp(name: String, email: String, password: String) async throws -> CommunitySession {
        let fields: [String: Any] = [
            "name": name,
            "email": email,
            "password": password,
            "passwordConfirm": password,
            "accepted_terms": true
        ]
        let body = try JSONSerialization.data(withJSONObject: fields)
        _ = try await client.send("POST", "/api/collections/users/records", body: .json(body))
        return try await signIn(email: email, password: password)
    }

    func signIn(email: String, password: String) async throws -> CommunitySession {
        let body = try JSONSerialization.data(withJSONObject: ["identity": email, "password": password])
        let response = try await client.send(AuthResponse.self, "POST", "/api/collections/users/auth-with-password",
                                             body: .json(body))
        return response.session
    }

    func refresh(_ session: CommunitySession) async throws -> CommunitySession {
        let response = try await client.send(AuthResponse.self, "POST", "/api/collections/users/auth-refresh",
                                             token: session.token)
        return response.session
    }

    func requestPasswordReset(email: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email])
        _ = try await client.send("POST", "/api/collections/users/request-password-reset", body: .json(body))
    }

    func rename(_ name: String, session: CommunitySession) async throws -> CommunityUser {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        let record = try await client.send(UserRecord.self, "PATCH", "/api/collections/users/records/\(session.user.id)",
                                           token: session.token, body: .json(body))
        return record.user(fallbackEmail: session.user.email)
    }

    func deleteAccount(_ session: CommunitySession) async throws {
        _ = try await client.send("DELETE", "/api/collections/users/records/\(session.user.id)", token: session.token)
    }

    // MARK: - Рецепты

    func recipes(_ query: CommunityQuery, page: Int, session: CommunitySession?) async throws -> CommunityPage<CommunityRecipe> {
        var conditions = ["published = true", "hidden = false"]
        if let category = query.category {
            conditions.append("category = \(PocketBaseFilter.quote(category.rawValue))")
        }
        conditions += query.words.map { "search ~ \(PocketBaseFilter.quote($0))" }
        conditions += query.excludedAuthors.prefix(30).map { "author != \(PocketBaseFilter.quote($0))" }
        let response = try await client.send(ListResponse<RecipeRecord>.self, "GET", "/api/collections/recipes/records",
                                              query: [
                                                  ("page", "\(page)"),
                                                  ("perPage", "\(Self.pageSize)"),
                                                  ("sort", query.sort == .best ? "-score,-created" : "-created"),
                                                  ("filter", PocketBaseFilter.all(conditions)),
                                                  ("expand", "author"),
                                                  ("skipTotal", "1")
                                              ],
                                              token: session?.token)
        return CommunityPage(items: response.items.map { makeRecipe($0) }, hasMore: response.items.count == Self.pageSize)
    }

    func recipes(byAuthor authorID: String, session: CommunitySession?) async throws -> [CommunityRecipe] {
        let response = try await client.send(ListResponse<RecipeRecord>.self, "GET", "/api/collections/recipes/records",
                                              query: [
                                                  ("perPage", "200"),
                                                  ("sort", "-created"),
                                                  ("filter", "author = \(PocketBaseFilter.quote(authorID))"),
                                                  ("expand", "author"),
                                                  ("skipTotal", "1")
                                              ],
                                              token: session?.token)
        return response.items.map { makeRecipe($0) }
    }

    func recipe(id: String, session: CommunitySession?) async throws -> CommunityRecipe {
        let record = try await client.send(RecipeRecord.self, "GET", "/api/collections/recipes/records/\(id)",
                                           query: [("expand", "author")], token: session?.token)
        return makeRecipe(record)
    }

    func saveRecipe(_ draft: RecipeDraft, id: String?, session: CommunitySession) async throws -> CommunityRecipe {
        let draft = draft.cleaned
        let payload = RecipePayload(author: id == nil ? session.user.id : nil,
                                    title: draft.title,
                                    summary: draft.summary,
                                    story: draft.story,
                                    category: draft.category.rawValue,
                                    country: draft.country ?? "",
                                    difficulty: min(max(draft.difficulty, 1), 3),
                                    prepMinutes: max(draft.prepMinutes, 0),
                                    cookMinutes: max(draft.cookMinutes, 0),
                                    servings: min(max(draft.servings, 1), 50),
                                    ingredients: draft.ingredients,
                                    steps: draft.steps,
                                    published: draft.isPublished,
                                    removedPhotos: id == nil || draft.removedPhotoNames.isEmpty ? nil : draft.removedPhotoNames)
        var form = MultipartForm()
        form.jsonPayload = try JSONEncoder().encode(payload)
        for photo in draft.newPhotos {
            form.addJPEG(field: id == nil ? "photos" : "photos+", data: photo)
        }
        let path = id.map { "/api/collections/recipes/records/\($0)" } ?? "/api/collections/recipes/records"
        let record = try await client.send(RecipeRecord.self, id == nil ? "POST" : "PATCH", path,
                                           query: [("expand", "author")], token: session.token,
                                           body: .multipart(form))
        return makeRecipe(record)
    }

    func deleteRecipe(id: String, session: CommunitySession) async throws {
        _ = try await client.send("DELETE", "/api/collections/recipes/records/\(id)", token: session.token)
    }

    // MARK: - Отзывы

    func reviews(for target: ReviewTarget, page: Int, excludedAuthors: [String]) async throws -> CommunityPage<CommunityReview> {
        var conditions = [Self.condition(for: target), "hidden = false"]
        conditions += excludedAuthors.prefix(30).map { "author != \(PocketBaseFilter.quote($0))" }
        let response = try await client.send(ListResponse<ReviewRecord>.self, "GET", "/api/collections/reviews/records",
                                              query: [
                                                  ("page", "\(page)"),
                                                  ("perPage", "\(Self.pageSize)"),
                                                  ("sort", "-created"),
                                                  ("filter", PocketBaseFilter.all(conditions)),
                                                  ("expand", "author"),
                                                  ("skipTotal", "1")
                                              ])
        return CommunityPage(items: response.items.map { makeReview($0) }, hasMore: response.items.count == Self.pageSize)
    }

    func myReview(for target: ReviewTarget, session: CommunitySession) async throws -> CommunityReview? {
        let conditions = [Self.condition(for: target), "author = \(PocketBaseFilter.quote(session.user.id))"]
        let response = try await client.send(ListResponse<ReviewRecord>.self, "GET", "/api/collections/reviews/records",
                                              query: [
                                                  ("perPage", "1"),
                                                  ("filter", PocketBaseFilter.all(conditions)),
                                                  ("expand", "author"),
                                                  ("skipTotal", "1")
                                              ],
                                              token: session.token)
        return response.items.first.map { makeReview($0) }
    }

    func saveReview(_ draft: ReviewDraft, for target: ReviewTarget, existingID: String?,
                    session: CommunitySession) async throws -> CommunityReview {
        var payload = ReviewPayload(rating: min(max(draft.rating, 1), 5),
                                    comment: draft.comment.trimmingCharacters(in: .whitespacesAndNewlines))
        if existingID == nil {
            payload.author = session.user.id
            switch target {
            case .community(let id): payload.recipe = id
            case .catalog(let id): payload.catalogID = id
            }
        }
        if draft.removesPhoto && draft.newPhoto == nil {
            payload.photo = ""
        }
        var form = MultipartForm()
        form.jsonPayload = try JSONEncoder().encode(payload)
        if let photo = draft.newPhoto {
            form.addJPEG(field: "photo", data: photo)
        }
        let path = existingID.map { "/api/collections/reviews/records/\($0)" } ?? "/api/collections/reviews/records"
        let record = try await client.send(ReviewRecord.self, existingID == nil ? "POST" : "PATCH", path,
                                           query: [("expand", "author")], token: session.token,
                                           body: .multipart(form))
        return makeReview(record)
    }

    func deleteReview(id: String, session: CommunitySession) async throws {
        _ = try await client.send("DELETE", "/api/collections/reviews/records/\(id)", token: session.token)
    }

    func catalogRatings() async throws -> [String: RatingSummary] {
        var result: [String: RatingSummary] = [:]
        var page = 1
        while page <= 20 {
            let response = try await client.send(ListResponse<CatalogRatingRecord>.self, "GET",
                                                  "/api/collections/catalog_ratings/records",
                                                  query: [("page", "\(page)"), ("perPage", "500"), ("skipTotal", "1")])
            for item in response.items {
                result[item.catalogID] = RatingSummary(average: item.ratingAverage ?? 0,
                                                       count: Int(item.ratingCount ?? 0))
            }
            guard response.items.count == 500 else { break }
            page += 1
        }
        return result
    }

    // MARK: - Жалобы

    func report(_ target: ReportTarget, reason: ReportReason, comment: String, session: CommunitySession) async throws {
        var body: [String: Any] = ["author": session.user.id, "reason": reason.rawValue,
                                   "comment": String(comment.prefix(1000))]
        switch target {
        case .recipe(let id): body["recipe"] = id
        case .review(let id): body["review"] = id
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await client.send("POST", "/api/collections/reports/records", token: session.token, body: .json(data))
    }

    // MARK: - Преобразование записей

    static func condition(for target: ReviewTarget) -> String {
        switch target {
        case .community(let id): "recipe = \(PocketBaseFilter.quote(id))"
        case .catalog(let id): "catalog_id = \(PocketBaseFilter.quote(id))"
        }
    }

    private func photo(collection: String, recordID: String, name: String) -> CommunityPhoto {
        CommunityPhoto(name: name,
                       url: client.fileURL(collectionID: collection, recordID: recordID, name: name),
                       thumbnailURL: client.fileURL(collectionID: collection, recordID: recordID, name: name,
                                                    thumb: "600x0"))
    }

    private func makeRecipe(_ record: RecipeRecord) -> CommunityRecipe {
        CommunityRecipe(id: record.id,
                        author: CommunityAuthor(id: record.author, name: record.expand?.author?.displayName ?? "Автор"),
                        title: record.title,
                        summary: record.summary ?? "",
                        story: record.story ?? "",
                        category: RecipeCategory(rawValue: record.category ?? "") ?? .main,
                        country: record.country?.nilIfBlank,
                        difficulty: Int(record.difficulty ?? 1),
                        prepMinutes: Int(record.prepMinutes ?? 0),
                        cookMinutes: Int(record.cookMinutes ?? 0),
                        servings: max(1, Int(record.servings ?? 1)),
                        ingredients: record.ingredients ?? [],
                        steps: record.steps ?? [],
                        photos: (record.photos ?? []).map { photo(collection: "recipes", recordID: record.id, name: $0) },
                        isPublished: record.published ?? false,
                        isHidden: record.hidden ?? false,
                        rating: RatingSummary(average: record.ratingAverage ?? 0, count: Int(record.ratingCount ?? 0)),
                        created: PocketBaseDate.parse(record.created) ?? .now)
    }

    private func makeReview(_ record: ReviewRecord) -> CommunityReview {
        let target: ReviewTarget = record.recipe?.nilIfBlank.map(ReviewTarget.community)
            ?? .catalog(record.catalogID ?? "")
        return CommunityReview(id: record.id,
                               author: CommunityAuthor(id: record.author,
                                                       name: record.expand?.author?.displayName ?? "Автор"),
                               target: target,
                               rating: Int(record.rating ?? 0),
                               comment: record.comment ?? "",
                               photo: record.photo?.nilIfBlank.map { photo(collection: "reviews", recordID: record.id, name: $0) },
                               isHidden: record.hidden ?? false,
                               created: PocketBaseDate.parse(record.created) ?? .now)
    }
}

// MARK: - Записи API

private struct ListResponse<Item: Decodable>: Decodable {
    let items: [Item]
}

private struct UserRecord: Decodable {
    let id: String
    let name: String?
    let email: String?

    var displayName: String { name?.nilIfBlank ?? "Автор" }

    func user(fallbackEmail: String = "") -> CommunityUser {
        CommunityUser(id: id, name: name ?? "", email: email ?? fallbackEmail)
    }
}

private struct AuthResponse: Decodable {
    let token: String
    let record: UserRecord

    var session: CommunitySession { CommunitySession(token: token, user: record.user()) }
}

private struct AuthorExpand: Decodable {
    let author: UserRecord?
}

private struct RecipeRecord: Decodable {
    let id: String
    let author: String
    let title: String
    let summary: String?
    let story: String?
    let category: String?
    let country: String?
    let difficulty: Double?
    let prepMinutes: Double?
    let cookMinutes: Double?
    let servings: Double?
    let ingredients: [CommunityIngredient]?
    let steps: [CommunityStep]?
    let photos: [String]?
    let published: Bool?
    let hidden: Bool?
    let ratingAverage: Double?
    let ratingCount: Double?
    let created: String?
    let expand: AuthorExpand?

    private enum CodingKeys: String, CodingKey {
        case id, author, title, summary, story, category, country, difficulty, servings, ingredients, steps, photos
        case published, hidden, created, expand
        case prepMinutes = "prep_minutes"
        case cookMinutes = "cook_minutes"
        case ratingAverage = "rating_avg"
        case ratingCount = "rating_count"
    }
}

private struct ReviewRecord: Decodable {
    let id: String
    let author: String
    let recipe: String?
    let catalogID: String?
    let rating: Double?
    let comment: String?
    let photo: String?
    let hidden: Bool?
    let created: String?
    let expand: AuthorExpand?

    private enum CodingKeys: String, CodingKey {
        case id, author, recipe, rating, comment, photo, hidden, created, expand
        case catalogID = "catalog_id"
    }
}

private struct CatalogRatingRecord: Decodable {
    let catalogID: String
    let ratingAverage: Double?
    let ratingCount: Double?

    private enum CodingKeys: String, CodingKey {
        case catalogID = "catalog_id"
        case ratingAverage = "rating_avg"
        case ratingCount = "rating_count"
    }
}

private struct RecipePayload: Encodable {
    let author: String?
    let title: String
    let summary: String
    let story: String
    let category: String
    let country: String
    let difficulty: Int
    let prepMinutes: Int
    let cookMinutes: Int
    let servings: Int
    let ingredients: [CommunityIngredient]
    let steps: [CommunityStep]
    let published: Bool
    let removedPhotos: [String]?

    private enum CodingKeys: String, CodingKey {
        case author, title, summary, story, category, country, difficulty, servings, ingredients, steps, published
        case prepMinutes = "prep_minutes"
        case cookMinutes = "cook_minutes"
        case removedPhotos = "photos-"
    }
}

private struct ReviewPayload: Encodable {
    var author: String?
    var recipe: String?
    var catalogID: String?
    let rating: Int
    let comment: String
    /// Пустая строка удаляет фото отзыва.
    var photo: String?

    init(rating: Int, comment: String) {
        self.rating = rating
        self.comment = comment
    }

    private enum CodingKeys: String, CodingKey {
        case author, recipe, rating, comment, photo
        case catalogID = "catalog_id"
    }
}
