import Foundation
import Observation
import Security

/// Где находится сервер сообщества.
enum CommunityConfig {
    /// Аргумент запуска `-CommunityURL http://127.0.0.1:8090` (для разработки и тестов)
    /// или ключ CommunityServer в Info.plist — он берётся из COMMUNITY_SERVER в Config/Shared.xcconfig.
    static var baseURL: URL? {
        if let override = UserDefaults.standard.string(forKey: "CommunityURL")?.nilIfBlank {
            return URL(string: override)
        }
        guard let value = (Bundle.main.object(forInfoDictionaryKey: "CommunityServer") as? String)?.nilIfBlank,
              !value.contains("$(") else { return nil }
        return URL(string: value.contains("://") ? value : "https://\(value)")
    }

    /// Почта для обращений по поводу контента — её требует App Store для приложений с публикациями.
    static var supportEmail: String? {
        guard let value = (Bundle.main.object(forInfoDictionaryKey: "CommunitySupportEmail") as? String)?.nilIfBlank,
              !value.contains("$(") else { return nil }
        return value
    }
}

/// Сессия хранится в Keychain: токен не попадает в резервные копии в открытом виде.
enum SessionKeychain {
    private static let service = "deshielo.community"
    private static let account = "session"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> CommunitySession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(CommunitySession.self, from: data)
    }

    static func save(_ session: CommunitySession?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }
}

/// Состояние сообщества для экранов: аккаунт, рейтинги каталога, скрытые авторы.
@MainActor
@Observable
final class CommunityStore {
    let service: (any CommunityService)?
    private(set) var session: CommunitySession?
    /// Рейтинги рецептов каталога: id → средняя оценка.
    private(set) var catalogRatings: [String: RatingSummary] = [:]
    /// Скрытые авторы: id → имя. Их рецепты и отзывы не показываются.
    private(set) var blockedAuthors: [String: String]
    /// Растёт при каждом изменении: экраны со списками перезагружаются.
    private(set) var revision = 0

    private let persistsSession: Bool
    private var cache: [String: CommunityRecipe] = [:]
    private static let blockedKey = "CommunityBlockedAuthors"

    init(service: (any CommunityService)?, session: CommunitySession? = nil, persistsSession: Bool = true) {
        self.service = service
        self.persistsSession = persistsSession
        self.session = session ?? (persistsSession && service != nil ? SessionKeychain.load() : nil)
        blockedAuthors = UserDefaults.standard.dictionary(forKey: Self.blockedKey) as? [String: String] ?? [:]
    }

    /// Сообщество для приложения: демо в отладочной сборке с -DemoData, иначе — сервер из настроек.
    static func make() -> CommunityStore {
        #if DEBUG
        if DemoData.isEnabled, UserDefaults.standard.string(forKey: "CommunityURL") == nil {
            return CommunityStore(service: DemoCommunityService(), session: DemoCommunityService.session,
                                  persistsSession: false)
        }
        #endif
        return CommunityStore(service: CommunityConfig.baseURL.map { PocketBaseCommunityService(baseURL: $0) })
    }

    var isConfigured: Bool { service != nil }
    var user: CommunityUser? { session?.user }

    func isMine(_ author: CommunityAuthor) -> Bool { author.id == session?.user.id }

    // MARK: - Аккаунт

    func signIn(email: String, password: String) async throws {
        let service = try requireService()
        setSession(try await service.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password))
    }

    func signUp(name: String, email: String, password: String) async throws {
        let service = try requireService()
        setSession(try await service.signUp(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                            email: email.trimmingCharacters(in: .whitespaces),
                                            password: password))
    }

    func requestPasswordReset(email: String) async throws {
        try await requireService().requestPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
    }

    func signOut() {
        setSession(nil)
    }

    /// Продлевает вход при запуске. Если токен устарел — выходит из аккаунта.
    func refreshSession() async {
        guard let service, let session else { return }
        do {
            setSession(try await service.refresh(session))
        } catch CommunityError.sessionExpired {
            setSession(nil)
        } catch {
            // Нет сети — остаёмся в аккаунте, попробуем в следующий раз.
        }
    }

    func rename(_ name: String) async throws {
        let session = try requireSession()
        let user = try await authorized { try await self.requireService().rename(name, session: session) }
        setSession(CommunitySession(token: session.token, user: user))
        revision += 1
    }

    func deleteAccount() async throws {
        let session = try requireSession()
        try await authorized { try await self.requireService().deleteAccount(session) }
        setSession(nil)
        cache = [:]
        revision += 1
        await loadCatalogRatings()
    }

    // MARK: - Рецепты

    func recipes(_ query: CommunityQuery, page: Int) async throws -> CommunityPage<CommunityRecipe> {
        var query = query
        query.excludedAuthors = Array(blockedAuthors.keys).sorted()
        let session = session
        let result = try await authorized { try await self.requireService().recipes(query, page: page, session: session) }
        let visible = result.items.filter { blockedAuthors[$0.author.id] == nil }
        visible.forEach { cache[$0.id] = $0 }
        return CommunityPage(items: visible, hasMore: result.hasMore)
    }

    func myRecipes() async throws -> [CommunityRecipe] {
        let session = try requireSession()
        return try await authorized {
            try await self.requireService().recipes(byAuthor: session.user.id, session: session)
        }
    }

    func cachedRecipe(_ id: String) -> CommunityRecipe? { cache[id] }

    func recipe(id: String) async throws -> CommunityRecipe {
        let session = session
        let recipe = try await authorized { try await self.requireService().recipe(id: id, session: session) }
        cache[id] = recipe
        return recipe
    }

    func saveRecipe(_ draft: RecipeDraft, id: String?) async throws -> CommunityRecipe {
        let session = try requireSession()
        let recipe = try await authorized {
            try await self.requireService().saveRecipe(draft, id: id, session: session)
        }
        cache[recipe.id] = recipe
        revision += 1
        return recipe
    }

    func deleteRecipe(id: String) async throws {
        let session = try requireSession()
        try await authorized { try await self.requireService().deleteRecipe(id: id, session: session) }
        cache[id] = nil
        revision += 1
    }

    // MARK: - Отзывы

    func reviews(for target: ReviewTarget, page: Int) async throws -> CommunityPage<CommunityReview> {
        let excluded = Array(blockedAuthors.keys).sorted()
        let result = try await authorized {
            try await self.requireService().reviews(for: target, page: page, excludedAuthors: excluded)
        }
        return CommunityPage(items: result.items.filter { blockedAuthors[$0.author.id] == nil }, hasMore: result.hasMore)
    }

    func myReview(for target: ReviewTarget) async throws -> CommunityReview? {
        guard let session else { return nil }
        return try await authorized { try await self.requireService().myReview(for: target, session: session) }
    }

    /// Публикует отзыв или обновляет уже оставленный.
    @discardableResult
    func saveReview(_ draft: ReviewDraft, for target: ReviewTarget, existingID: String?) async throws -> CommunityReview {
        let session = try requireSession()
        var existingID = existingID
        if existingID == nil {
            existingID = try await myReview(for: target)?.id
        }
        let id = existingID
        let review = try await authorized {
            try await self.requireService().saveReview(draft, for: target, existingID: id, session: session)
        }
        await afterReviewChange(target)
        return review
    }

    func deleteReview(_ review: CommunityReview) async throws {
        let session = try requireSession()
        try await authorized { try await self.requireService().deleteReview(id: review.id, session: session) }
        await afterReviewChange(review.target)
    }

    private func afterReviewChange(_ target: ReviewTarget) async {
        if case .community(let id) = target {
            cache[id] = nil
        } else {
            await loadCatalogRatings()
        }
        revision += 1
    }

    func rating(forCatalog id: String) -> RatingSummary? {
        catalogRatings[id].flatMap { $0.count > 0 ? $0 : nil }
    }

    func loadCatalogRatings() async {
        guard let service else { return }
        if let ratings = try? await service.catalogRatings() {
            catalogRatings = ratings
        }
    }

    // MARK: - Жалобы и скрытые авторы

    func report(_ target: ReportTarget, reason: ReportReason, comment: String) async throws {
        let session = try requireSession()
        try await authorized {
            try await self.requireService().report(target, reason: reason, comment: comment, session: session)
        }
    }

    func block(_ author: CommunityAuthor) {
        guard !isMine(author) else { return }
        blockedAuthors[author.id] = author.name
        saveBlocked()
    }

    func unblock(_ id: String) {
        blockedAuthors[id] = nil
        saveBlocked()
    }

    func isBlocked(_ author: CommunityAuthor) -> Bool { blockedAuthors[author.id] != nil }

    private func saveBlocked() {
        UserDefaults.standard.set(blockedAuthors, forKey: Self.blockedKey)
        revision += 1
    }

    // MARK: - Служебное

    private func requireService() throws -> any CommunityService {
        guard let service else { throw CommunityError.notConfigured }
        return service
    }

    private func requireSession() throws -> CommunitySession {
        guard let session else { throw CommunityError.notSignedIn }
        return session
    }

    private func setSession(_ session: CommunitySession?) {
        self.session = session
        if persistsSession {
            SessionKeychain.save(session)
        }
    }

    /// Выполняет запрос; если сервер не принял токен — выходит из аккаунта.
    private func authorized<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch CommunityError.sessionExpired {
            setSession(nil)
            throw CommunityError.sessionExpired
        }
    }
}
