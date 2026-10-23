#if DEBUG
import Foundation

/// Сообщество без сервера: данные в памяти. Включается аргументом запуска -DemoData
/// и нужно для скриншотов и UI-тестов. Фото — генеративные обложки (адреса demo://).
struct DemoCommunityService: CommunityService {
    static let user = CommunityUser(id: "demo-maria", name: "Мария", email: "maria@example.com")
    static let session = CommunitySession(token: "demo", user: user)

    private let storage = DemoCommunityStorage()

    func signUp(name: String, email: String, password: String) async throws -> CommunitySession {
        CommunitySession(token: "demo", user: CommunityUser(id: Self.user.id, name: name, email: email))
    }

    func signIn(email: String, password: String) async throws -> CommunitySession { Self.session }

    func refresh(_ session: CommunitySession) async throws -> CommunitySession { session }

    func requestPasswordReset(email: String) async throws {}

    func rename(_ name: String, session: CommunitySession) async throws -> CommunityUser {
        CommunityUser(id: session.user.id, name: name, email: session.user.email)
    }

    func deleteAccount(_ session: CommunitySession) async throws {
        await storage.removeAuthor(session.user.id)
    }

    func recipes(_ query: CommunityQuery, page: Int, session: CommunitySession?) async throws -> CommunityPage<CommunityRecipe> {
        let all = await storage.recipes.filter { recipe in
            guard recipe.isPublished, !recipe.isHidden, !query.excludedAuthors.contains(recipe.author.id) else { return false }
            if let category = query.category, recipe.category != category { return false }
            let text = ([recipe.title, recipe.summary] + recipe.ingredients.map(\.name)).joined(separator: " ")
                .lowercased().replacingOccurrences(of: "ё", with: "е")
            return query.words.allSatisfy { text.contains($0) }
        }
        let sorted = query.sort == .best
            ? all.sorted { $0.rating.average > $1.rating.average }
            : all.sorted { $0.created > $1.created }
        return CommunityPage(items: page == 1 ? sorted : [], hasMore: false)
    }

    func recipes(byAuthor authorID: String, session: CommunitySession?) async throws -> [CommunityRecipe] {
        await storage.recipes.filter { $0.author.id == authorID }.sorted { $0.created > $1.created }
    }

    func recipe(id: String, session: CommunitySession?) async throws -> CommunityRecipe {
        guard let recipe = await storage.recipes.first(where: { $0.id == id }) else { throw CommunityError.notFound }
        return recipe
    }

    func saveRecipe(_ draft: RecipeDraft, id: String?, session: CommunitySession) async throws -> CommunityRecipe {
        try await storage.saveRecipe(draft.cleaned, id: id, author: CommunityAuthor(id: session.user.id, name: session.user.name))
    }

    func deleteRecipe(id: String, session: CommunitySession) async throws {
        await storage.deleteRecipe(id)
    }

    func reviews(for target: ReviewTarget, page: Int, excludedAuthors: [String]) async throws -> CommunityPage<CommunityReview> {
        let items = await storage.reviews
            .filter { $0.target == target && !$0.isHidden && !excludedAuthors.contains($0.author.id) }
            .sorted { $0.created > $1.created }
        return CommunityPage(items: page == 1 ? items : [], hasMore: false)
    }

    func myReview(for target: ReviewTarget, session: CommunitySession) async throws -> CommunityReview? {
        await storage.reviews.first { $0.target == target && $0.author.id == session.user.id }
    }

    func saveReview(_ draft: ReviewDraft, for target: ReviewTarget, existingID: String?,
                    session: CommunitySession) async throws -> CommunityReview {
        await storage.saveReview(draft, target: target, existingID: existingID,
                                 author: CommunityAuthor(id: session.user.id, name: session.user.name))
    }

    func deleteReview(id: String, session: CommunitySession) async throws {
        await storage.deleteReview(id)
    }

    func catalogRatings() async throws -> [String: RatingSummary] {
        await storage.catalogRatings()
    }

    func report(_ target: ReportTarget, reason: ReportReason, comment: String, session: CommunitySession) async throws {}
}

/// Генеративное «фото» для демо-режима: адрес вида demo://photo/<палитра>/<номер>.
enum DemoPhoto {
    static let scheme = "demo"

    static let palettes: [[String]] = [
        ["#E9B949", "#F6E7C8", "#C8243B"], ["#D9822B", "#F3E3B5", "#5E7F37"], ["#8E2347", "#F1D6C8", "#3A5A40"],
        ["#B4532A", "#F6E7C8", "#7A9E3F"], ["#C9A24B", "#FFF4D6", "#8C3B2A"], ["#5C3D2E", "#E8C77A", "#B4532A"],
        ["#E07A4F", "#FBE8D3", "#2F4858"], ["#6B8E23", "#F0E6C8", "#C8243B"]
    ]

    static func photo(_ palette: Int, _ number: Int) -> CommunityPhoto {
        let url = URL(string: "\(scheme)://photo/\(palette % palettes.count)/\(number)")!
        return CommunityPhoto(name: "demo-\(palette)-\(number)", url: url, thumbnailURL: url)
    }

    static func recipe(for url: URL) -> Recipe {
        let parts = url.pathComponents.filter { $0 != "/" }
        let index = parts.first.flatMap(Int.init) ?? 0
        return .artworkPlaceholder(id: "demo-photo-\(parts.joined(separator: "-"))",
                                   palette: palettes[index % palettes.count])
    }
}

/// Хранилище демо-данных.
actor DemoCommunityStorage {
    private(set) var recipes: [CommunityRecipe]
    private(set) var reviews: [CommunityReview]
    private var counter = 100

    init() {
        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        let olga = CommunityAuthor(id: "demo-olga", name: "Ольга К.")
        let alexey = CommunityAuthor(id: "demo-alexey", name: "Алексей Петров")
        let timur = CommunityAuthor(id: "demo-timur", name: "Тимур")
        let natasha = CommunityAuthor(id: "demo-natasha", name: "Наташа")
        let sveta = CommunityAuthor(id: "demo-sveta", name: "Света из Казани")
        let maria = CommunityAuthor(id: DemoCommunityService.user.id, name: DemoCommunityService.user.name)

        func ingredient(_ name: String, _ amount: Double? = nil, _ unit: String? = nil, note: String? = nil) -> CommunityIngredient {
            CommunityIngredient(name: name, amount: amount, unit: unit, note: note)
        }

        recipes = [
            CommunityRecipe(id: "demo-pumpkin-soup", author: alexey,
                            title: "Тыквенный суп с имбирём и кокосовым молоком",
                            summary: "Бархатный, яркий и согревающий. Готовится за 40 минут из простых продуктов.",
                            story: "Этот суп я впервые попробовал на рынке в Тбилиси осенью — и с тех пор варю его каждую неделю, пока есть тыква.",
                            category: .soup, country: nil, difficulty: 1, prepMinutes: 15, cookMinutes: 30, servings: 4,
                            ingredients: [ingredient("Тыква", 800, "g", note: "очищенная"), ingredient("Лук репчатый", 1, "pcs"),
                                          ingredient("Имбирь", 20, "g"), ingredient("Кокосовое молоко", 400, "ml"),
                                          ingredient("Овощной бульон", 500, "ml"), ingredient("Соль", nil, "toTaste")],
                            steps: [CommunityStep(title: "Обжарьте", text: "Обжарьте лук и тёртый имбирь на масле до мягкости.", timer: 5),
                                    CommunityStep(title: "Варите", text: "Добавьте тыкву кубиками и бульон, варите до мягкости.", timer: 20),
                                    CommunityStep(title: "Пюрируйте", text: "Влейте кокосовое молоко и пробейте блендером до гладкости.")],
                            photos: [DemoPhoto.photo(1, 1), DemoPhoto.photo(6, 2)], isPublished: true, isHidden: false,
                            rating: RatingSummary(average: 4.7, count: 18), created: ago(5)),
            CommunityRecipe(id: "demo-syrniki", author: olga,
                            title: "Бабушкины сырники с изюмом",
                            summary: "Пышные, с хрустящей корочкой и изюмом. Секрет — творог из-под пресса и капля коньяка в изюм.",
                            story: "", category: .breakfast, country: "RU", difficulty: 1, prepMinutes: 15, cookMinutes: 15, servings: 3,
                            ingredients: [ingredient("Творог 9%", 500, "g"), ingredient("Яйцо", 1, "pcs"),
                                          ingredient("Мука", 4, "tbsp"), ingredient("Сахар", 2, "tbsp"), ingredient("Изюм", 50, "g")],
                            steps: [CommunityStep(title: "Изюм", text: "Залейте изюм кипятком на 10 минут и обсушите.", timer: 10),
                                    CommunityStep(title: "Тесто", text: "Разомните творог с яйцом, сахаром и мукой, вмешайте изюм."),
                                    CommunityStep(title: "Обжарьте", text: "Сформируйте шайбы и обжарьте по 3 минуты с каждой стороны.", timer: 6)],
                            photos: [DemoPhoto.photo(0, 3)], isPublished: true, isHidden: false,
                            rating: RatingSummary(average: 4.9, count: 32), created: ago(26)),
            CommunityRecipe(id: "demo-megruli", author: timur,
                            title: "Мегрельский хачапури в духовке",
                            summary: "Две начинки из сулугуни: внутри и сверху. Тесто на мацони — мягкое и тянущееся.",
                            story: "Рецепт моей тёти из Зугдиди. Главное — не жалеть сыра и раскатывать тесто руками, а не скалкой.",
                            category: .baking, country: "GE", difficulty: 2, prepMinutes: 30, cookMinutes: 15, servings: 4,
                            ingredients: [ingredient("Мука", 500, "g"), ingredient("Мацони или кефир", 300, "ml"),
                                          ingredient("Сулугуни", 600, "g"), ingredient("Яйцо", 1, "pcs"), ingredient("Сливочное масло", 30, "g")],
                            steps: [CommunityStep(title: "Тесто", text: "Замесите мягкое тесто из муки, мацони и щепотки соли, дайте отдохнуть.", timer: 30),
                                    CommunityStep(title: "Начинка", text: "Натрите сыр и смешайте две трети с яйцом."),
                                    CommunityStep(title: "Выпекайте", text: "Сформируйте лепёшку с начинкой, посыпьте сыром и выпекайте при 230 °C.", timer: 12)],
                            photos: [DemoPhoto.photo(4, 4), DemoPhoto.photo(5, 5), DemoPhoto.photo(0, 6)], isPublished: true,
                            isHidden: false, rating: RatingSummary(average: 4.8, count: 41), created: ago(50)),
            CommunityRecipe(id: "demo-sharlotka", author: natasha,
                            title: "Шарлотка с антоновкой",
                            summary: "Самая простая и самая любимая: три яйца, стакан сахара, стакан муки и много кислых яблок.",
                            story: "", category: .baking, country: "RU", difficulty: 1, prepMinutes: 15, cookMinutes: 40, servings: 6,
                            ingredients: [ingredient("Яблоки антоновка", 4, "pcs"), ingredient("Яйцо", 3, "pcs"),
                                          ingredient("Сахар", 180, "g"), ingredient("Мука", 160, "g"), ingredient("Корица", 1, "tsp")],
                            steps: [CommunityStep(title: "Взбейте", text: "Взбейте яйца с сахаром в пышную светлую массу.", timer: 7),
                                    CommunityStep(title: "Соедините", text: "Вмешайте муку лопаткой, выложите на нарезанные яблоки."),
                                    CommunityStep(title: "Выпекайте", text: "Выпекайте при 180 °C до сухой шпажки.", timer: 40)],
                            photos: [DemoPhoto.photo(3, 7)], isPublished: true, isHidden: false,
                            rating: RatingSummary(average: 4.6, count: 23), created: ago(80)),
            CommunityRecipe(id: "demo-okroshka", author: sveta,
                            title: "Окрошка на квасе, как в детстве",
                            summary: "Холодный летний суп: редиска, огурцы, картофель, яйца и много зелени.",
                            story: "", category: .soup, country: "RU", difficulty: 1, prepMinutes: 25, cookMinutes: 20, servings: 4,
                            ingredients: [ingredient("Квас", 1.5, "l"), ingredient("Картофель", 3, "pcs"), ingredient("Огурцы", 2, "pcs"),
                                          ingredient("Редиска", 8, "pcs"), ingredient("Яйцо", 3, "pcs"), ingredient("Укроп", 1, "bunch")],
                            steps: [CommunityStep(title: "Отварите", text: "Отварите картофель и яйца, остудите.", timer: 20),
                                    CommunityStep(title: "Нарежьте", text: "Нарежьте всё мелким кубиком, зелень — мелко."),
                                    CommunityStep(title: "Залейте", text: "Перед подачей залейте холодным квасом, добавьте сметану.")],
                            photos: [DemoPhoto.photo(7, 8)], isPublished: true, isHidden: false,
                            rating: RatingSummary(average: 4.4, count: 9), created: ago(120)),
            CommunityRecipe(id: "demo-maria-pasta", author: maria,
                            title: "Паста с тыквой, шалфеем и пармезаном",
                            summary: "Осенняя паста за 25 минут: запечённая тыква, хрустящий шалфей и коричневое масло.",
                            story: "", category: .main, country: "IT", difficulty: 1, prepMinutes: 10, cookMinutes: 25, servings: 2,
                            ingredients: [ingredient("Паста", 250, "g"), ingredient("Тыква", 300, "g"),
                                          ingredient("Сливочное масло", 40, "g"), ingredient("Шалфей", 8, "leaf"), ingredient("Пармезан", 40, "g")],
                            steps: [CommunityStep(title: "Тыква", text: "Запеките тыкву кубиками при 200 °C до мягкости.", timer: 20),
                                    CommunityStep(title: "Масло", text: "Растопите масло с шалфеем до орехового запаха."),
                                    CommunityStep(title: "Соедините", text: "Смешайте пасту с тыквой и маслом, посыпьте пармезаном.")],
                            photos: [DemoPhoto.photo(1, 9)], isPublished: true, isHidden: false,
                            rating: RatingSummary(average: 4.5, count: 4), created: ago(200)),
            CommunityRecipe(id: "demo-maria-draft", author: maria,
                            title: "Пирог с капустой (черновик)",
                            summary: "Дрожжевой пирог по маминому рецепту — ещё дописываю.",
                            story: "", category: .baking, country: "RU", difficulty: 2, prepMinutes: 40, cookMinutes: 40, servings: 8,
                            ingredients: [ingredient("Капуста", 1, "kg"), ingredient("Мука", 500, "g")],
                            steps: [CommunityStep(title: nil, text: "Потушите капусту с луком до мягкости.", timer: 30)],
                            photos: [], isPublished: false, isHidden: false, rating: .empty, created: ago(2))
        ]

        let catalogReviews: [(String, CommunityAuthor, Int, String, Int?)] = [
            ("beef-wellington", olga, 5, "Готовила на Новый год — все были в восторге. Дюксель обязательно хорошо выпарить!", 2),
            ("beef-wellington", timur, 4, "Получилось с первого раза, но тесто снизу чуть размокло. В следующий раз добавлю блинчики толще.", 5),
            ("beef-wellington", sveta, 5, "Термометр — лучший друг: вынула при 52 °C, идеальная прожарка.", nil),
            ("plov", alexey, 5, "Сделал на даче в казане — соседи пришли на запах.", 4),
            ("carbonara", natasha, 5, "Наконец-то без сливок и без омлета. Спасибо за подробный шаг с эмульсией!", 0),
            ("syrniki", olga, 5, "Добавила ваниль и цедру лимона — очень нежные.", 3),
            ("tuhu", timur, 4, "Неожиданно вкусно для блюда, которому почти 4000 лет. Пиво взял нефильтрованное.", 2)
        ]
        var reviews: [CommunityReview] = catalogReviews.enumerated().map { index, item in
            CommunityReview(id: "demo-review-\(index)", author: item.1, target: .catalog(item.0), rating: item.2,
                            comment: item.3, photo: item.4.map { DemoPhoto.photo($0, 20 + index) }, isHidden: false,
                            created: ago(Double(index * 9 + 3)))
        }
        reviews += [
            CommunityReview(id: "demo-review-pumpkin-1", author: natasha, target: .community("demo-pumpkin-soup"), rating: 5,
                            comment: "Добавила обжаренные тыквенные семечки сверху — шикарно!", photo: DemoPhoto.photo(6, 40),
                            isHidden: false, created: ago(3)),
            CommunityReview(id: "demo-review-pumpkin-2", author: olga, target: .community("demo-pumpkin-soup"), rating: 4,
                            comment: "Вкусно, но имбиря для детей многовато — в следующий раз положу половину.", photo: nil,
                            isHidden: false, created: ago(30)),
            CommunityReview(id: "demo-review-megruli", author: maria, target: .community("demo-megruli"), rating: 5,
                            comment: "Тесто на мацони — открытие. Сыр тянется, как на фото.", photo: DemoPhoto.photo(4, 41),
                            isHidden: false, created: ago(12))
        ]
        self.reviews = reviews
    }

    func saveRecipe(_ draft: RecipeDraft, id: String?, author: CommunityAuthor) throws -> CommunityRecipe {
        counter += 1
        let existing = id.flatMap { id in recipes.first { $0.id == id } }
        let photos = draft.keptPhotos.filter { !draft.removedPhotoNames.contains($0.name) }
            + draft.newPhotos.indices.map { DemoPhoto.photo(counter + $0, counter * 10 + $0) }
        let recipe = CommunityRecipe(id: existing?.id ?? "demo-new-\(counter)", author: existing?.author ?? author,
                                     title: draft.title, summary: draft.summary, story: draft.story,
                                     category: draft.category, country: draft.country, difficulty: draft.difficulty,
                                     prepMinutes: draft.prepMinutes, cookMinutes: draft.cookMinutes, servings: draft.servings,
                                     ingredients: draft.ingredients, steps: draft.steps, photos: photos,
                                     isPublished: draft.isPublished, isHidden: existing?.isHidden ?? false,
                                     rating: existing?.rating ?? .empty, created: existing?.created ?? .now)
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        return recipe
    }

    func deleteRecipe(_ id: String) {
        recipes.removeAll { $0.id == id }
        reviews.removeAll { $0.target == .community(id) }
    }

    func saveReview(_ draft: ReviewDraft, target: ReviewTarget, existingID: String?, author: CommunityAuthor) -> CommunityReview {
        counter += 1
        let existing = existingID.flatMap { id in reviews.first { $0.id == id } }
        var photo = draft.removesPhoto ? nil : existing?.photo
        if draft.newPhoto != nil {
            photo = DemoPhoto.photo(counter, counter)
        }
        let review = CommunityReview(id: existing?.id ?? "demo-review-new-\(counter)", author: author, target: target,
                                     rating: draft.rating, comment: draft.comment, photo: photo, isHidden: false,
                                     created: existing?.created ?? .now)
        if let index = reviews.firstIndex(where: { $0.id == review.id }) {
            reviews[index] = review
        } else {
            reviews.insert(review, at: 0)
        }
        refreshRating(target)
        return review
    }

    func deleteReview(_ id: String) {
        guard let review = reviews.first(where: { $0.id == id }) else { return }
        reviews.removeAll { $0.id == id }
        refreshRating(review.target)
    }

    func removeAuthor(_ id: String) {
        recipes.removeAll { $0.author.id == id }
        reviews.removeAll { $0.author.id == id }
    }

    func catalogRatings() -> [String: RatingSummary] {
        var result: [String: RatingSummary] = [
            "beef-wellington": RatingSummary(average: 4.7, count: 26), "plov": RatingSummary(average: 4.9, count: 31),
            "carbonara": RatingSummary(average: 4.8, count: 57), "syrniki": RatingSummary(average: 4.8, count: 44),
            "tuhu": RatingSummary(average: 4.2, count: 11), "pho-bo": RatingSummary(average: 4.6, count: 15)
        ]
        // Свои отзывы на рецепты без готового рейтинга считаются честно.
        for case .catalog(let id) in Set(reviews.map(\.target)) where result[id] == nil {
            let ratings = reviews.filter { $0.target == .catalog(id) }.map(\.rating)
            result[id] = RatingSummary(average: Double(ratings.reduce(0, +)) / Double(ratings.count), count: ratings.count)
        }
        return result
    }

    private func refreshRating(_ target: ReviewTarget) {
        guard case .community(let id) = target, let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        let ratings = reviews.filter { $0.target == target && !$0.isHidden }.map(\.rating)
        recipes[index].rating = ratings.isEmpty
            ? .empty
            : RatingSummary(average: (Double(ratings.reduce(0, +)) / Double(ratings.count) * 10).rounded() / 10,
                            count: ratings.count)
    }
}
#endif
