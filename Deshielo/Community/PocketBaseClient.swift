import Foundation

/// Тонкий клиент REST API PocketBase: запросы, загрузка файлов и разбор ошибок.
/// Схема данных сервера — в папке server/ репозитория.
struct PocketBaseClient: Sendable {
    let baseURL: URL
    var urlSession: URLSession = .shared

    enum Body: Sendable {
        case none
        case json(Data)
        case multipart(MultipartForm)
    }

    /// Выполняет запрос и возвращает тело ответа. Ошибки сервера переводятся в CommunityError.
    func send(_ method: String, _ path: String, query: [(String, String)] = [], token: String? = nil,
              body: Body = .none) async throws -> Data {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        switch body {
        case .none:
            break
        case .json(let data):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        case .multipart(let form):
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = form.encoded()
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            // Экран ушёл или запрос сменился — это не ошибка сети.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw CommunityError.network
        }
        guard let http = response as? HTTPURLResponse else { throw CommunityError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw PocketBaseErrorMapper.error(status: http.statusCode, body: data, path: path)
        }
        return data
    }

    func send<T: Decodable>(_ type: T.Type, _ method: String, _ path: String, query: [(String, String)] = [],
                            token: String? = nil, body: Body = .none) async throws -> T {
        let data = try await send(method, path, query: query, token: token, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CommunityError.server("Не удалось прочитать ответ сервера. Обновите приложение.")
        }
    }

    func url(_ path: String, query: [(String, String)] = []) -> URL {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        var string = base + path
        if !query.isEmpty {
            string += "?" + query.map { "\(Self.percentEncode($0.0))=\(Self.percentEncode($0.1))" }.joined(separator: "&")
        }
        return URL(string: string) ?? baseURL
    }

    func fileURL(collectionID: String, recordID: String, name: String, thumb: String? = nil) -> URL {
        url("/api/files/\(collectionID)/\(recordID)/\(Self.percentEncode(name))",
            query: thumb.map { [("thumb", $0)] } ?? [])
    }

    /// Строгое кодирование: «+», «&» и «=» в фильтре не должны потеряться по дороге.
    static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

/// Строки фильтров PocketBase.
enum PocketBaseFilter {
    /// Значение в кавычках с экранированием: пользовательский ввод не может сломать фильтр.
    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func all(_ conditions: [String]) -> String {
        conditions.filter { !$0.isEmpty }.joined(separator: " && ")
    }
}

/// Тело запроса multipart/form-data: обычные поля одной частью @jsonPayload, затем файлы.
struct MultipartForm: Sendable {
    struct FilePart: Sendable {
        let field: String
        let filename: String
        let mimeType: String
        let data: Data
    }

    let boundary: String
    var jsonPayload: Data?
    var files: [FilePart] = []

    init(boundary: String = "deshielo-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addJPEG(field: String, data: Data) {
        files.append(FilePart(field: field, filename: "photo-\(files.count + 1).jpg", mimeType: "image/jpeg", data: data))
    }

    func encoded() -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        if let jsonPayload {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"@jsonPayload\"\r\n")
            append("Content-Type: application/json\r\n\r\n")
            body.append(jsonPayload)
            append("\r\n")
        }
        for file in files {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.filename)\"\r\n")
            append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }
}

/// Даты PocketBase: «2026-10-22 20:48:05.123Z».
enum PocketBaseDate {
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let iso = string.replacingOccurrences(of: " ", with: "T")
        return withFraction.date(from: iso) ?? plain.date(from: iso)
    }

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()
}

/// Переводит ответы сервера с ошибкой в понятные сообщения.
enum PocketBaseErrorMapper {
    private struct Body: Decodable {
        struct FieldError: Decodable {
            let code: String?
            let message: String?
        }

        let message: String?
        let data: [String: FieldError]?
    }

    static func error(status: Int, body: Data, path: String) -> CommunityError {
        let decoded = try? JSONDecoder().decode(Body.self, from: body)
        switch status {
        case 401:
            return .sessionExpired
        case 404:
            return .notFound
        case 429:
            return .rateLimited
        case 500...:
            return .server("Сервер сообщества временно недоступен. Попробуйте позже.")
        default:
            break
        }
        // Сообщения хуков сервера уже написаны по-русски.
        if let message = decoded?.message, message.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) != nil {
            return .server(message)
        }
        if let fields = decoded?.data, !fields.isEmpty {
            return .server(fieldMessage(fields.mapValues { (code: $0.code ?? "", message: $0.message ?? "") }, path: path))
        }
        if path.hasSuffix("auth-with-password") {
            return .server("Неверная почта или пароль.")
        }
        if status == 403 {
            return .server("Недостаточно прав для этого действия.")
        }
        return .server("Сервер отклонил запрос. Проверьте данные и попробуйте ещё раз.")
    }

    static func fieldMessage(_ fields: [String: (code: String, message: String)], path: String) -> String {
        if fields["email"]?.code == "validation_not_unique" {
            return "Эта почта уже зарегистрирована. Войдите или восстановите пароль."
        }
        if fields.values.contains(where: { $0.code == "validation_not_unique" }) {
            if path.contains("/reviews/") { return "Вы уже оставили отзыв на этот рецепт." }
            if path.contains("/reports/") { return "Вы уже отправили жалобу — спасибо!" }
        }
        if fields["passwordConfirm"]?.code == "validation_values_mismatch" {
            return "Пароли не совпадают."
        }
        // Поля в порядке важности для пользователя.
        let order = ["email", "password", "name", "accepted_terms", "title", "photos", "photo", "rating", "comment"]
        let name = order.first { fields[$0] != nil } ?? fields.keys.sorted().first ?? ""
        let code = fields[name]?.code ?? ""
        let label = labels[name] ?? name
        switch (name, code) {
        case ("password", "validation_min_text_constraint"):
            return "Пароль должен быть не короче 8 символов."
        case ("accepted_terms", _):
            return "Чтобы продолжить, примите правила сообщества."
        case (_, "validation_required"):
            return "Заполните поле «\(label)»."
        case (_, "validation_is_email"):
            return "Проверьте адрес почты."
        case (_, "validation_min_text_constraint"):
            return "Поле «\(label)» слишком короткое."
        case (_, "validation_max_text_constraint"):
            return "Поле «\(label)» слишком длинное."
        case (_, "validation_file_size_limit"):
            return "Фото слишком большое."
        case (_, "validation_invalid_mime_type"):
            return "Этот формат фото не поддерживается — выберите JPEG или PNG."
        case (_, "validation_too_many_files"):
            return "Слишком много фото: не больше \(RecipeDraft.maxPhotos)."
        default:
            return "Проверьте поле «\(label)»."
        }
    }

    private static let labels = [
        "email": "Почта", "password": "Пароль", "passwordConfirm": "Повтор пароля", "name": "Имя",
        "title": "Название", "summary": "Описание", "story": "История блюда", "category": "Категория",
        "country": "Страна", "difficulty": "Сложность", "servings": "Порции", "prep_minutes": "Подготовка",
        "cook_minutes": "Готовка", "ingredients": "Ингредиенты", "steps": "Шаги", "photos": "Фото",
        "photo": "Фото", "rating": "Оценка", "comment": "Отзыв", "reason": "Причина"
    ]
}
