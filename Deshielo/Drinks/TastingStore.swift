import Foundation
import Observation

/// Запись дегустационного дневника: какое вино или чай, оценка, ароматы, заметка и фото этикетки.
struct Tasting: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case wine, tea

        var id: String { rawValue }

        var title: String {
            switch self {
            case .wine: "Вино"
            case .tea: "Чай"
            }
        }

        var symbol: String {
            switch self {
            case .wine: "wineglass"
            case .tea: "cup.and.saucer"
            }
        }
    }

    var id: UUID
    var kind: Kind
    var name: String
    var date: Date
    /// Год урожая — для вина.
    var vintage: Int?
    var styleID: String?
    var grapeID: String?
    var regionID: String?
    var teaID: String?
    /// Оценка от 1 до 5.
    var rating: Int?
    var aromas: [String]
    var note: String?
    /// Имя файла фото в папке JournalPhotos.
    var photo: String?
    /// С каким блюдом пробовали.
    var recipeID: String?

    init(id: UUID = UUID(), kind: Kind, name: String, date: Date = .now, vintage: Int? = nil,
         styleID: String? = nil, grapeID: String? = nil, regionID: String? = nil, teaID: String? = nil,
         rating: Int? = nil, aromas: [String] = [], note: String? = nil, photo: String? = nil,
         recipeID: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.date = date
        self.vintage = vintage
        self.styleID = styleID
        self.grapeID = grapeID
        self.regionID = regionID
        self.teaID = teaID
        self.rating = rating
        self.aromas = aromas
        self.note = note
        self.photo = photo
        self.recipeID = recipeID
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, date, vintage, styleID, grapeID, regionID, teaID, rating, aromas, note, photo, recipeID
    }

    // Новые поля можно добавлять без потери старых записей.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        vintage = try? c.decodeIfPresent(Int.self, forKey: .vintage)
        styleID = try? c.decodeIfPresent(String.self, forKey: .styleID)
        grapeID = try? c.decodeIfPresent(String.self, forKey: .grapeID)
        regionID = try? c.decodeIfPresent(String.self, forKey: .regionID)
        teaID = try? c.decodeIfPresent(String.self, forKey: .teaID)
        rating = try? c.decodeIfPresent(Int.self, forKey: .rating)
        aromas = (try? c.decodeIfPresent([String].self, forKey: .aromas)) ?? []
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        photo = try? c.decodeIfPresent(String.self, forKey: .photo)
        recipeID = try? c.decodeIfPresent(String.self, forKey: .recipeID)
    }

    /// «Château Margaux 2015».
    var displayName: String {
        guard let vintage else { return name }
        return "\(name) \(vintage)"
    }
}

enum TastingStorage {
    static var file: JSONFile<[Tasting]> { JSONFile(url: AppGroup.fileURL("tastings.json")) }

    static func load() -> [Tasting] { file.read() ?? [] }

    static func save(_ tastings: [Tasting]) { file.write(tastings) }
}

/// Дегустационный дневник. Хранится на устройстве рядом с профилем, фото — в JournalPhotos.
@MainActor
@Observable
final class TastingStore {
    private(set) var tastings: [Tasting]

    init(tastings: [Tasting]? = nil) {
        self.tastings = (tastings ?? TastingStorage.load()).sorted { $0.date > $1.date }
    }

    func tastings(of kind: Tasting.Kind?) -> [Tasting] {
        guard let kind else { return tastings }
        return tastings.filter { $0.kind == kind }
    }

    /// Записи о конкретном сорте, регионе или чае — для их страниц.
    func tastings(grape id: String) -> [Tasting] { tastings.filter { $0.grapeID == id } }
    func tastings(tea id: String) -> [Tasting] { tastings.filter { $0.teaID == id } }

    /// Добавить новую запись или сохранить изменения в существующей.
    func save(_ tasting: Tasting) {
        var entry = tasting
        entry.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = entry.note?.nilIfBlank
        if let index = tastings.firstIndex(where: { $0.id == entry.id }) {
            if tastings[index].photo != entry.photo {
                JournalPhotos.delete(tastings[index].photo)
            }
            tastings[index] = entry
        } else {
            tastings.append(entry)
        }
        tastings.sort { $0.date > $1.date }
        TastingStorage.save(tastings)
    }

    func delete(_ tasting: Tasting) {
        tastings.removeAll { $0.id == tasting.id }
        JournalPhotos.delete(tasting.photo)
        TastingStorage.save(tastings)
    }

    /// Сброс личных данных из настроек.
    func resetAll() {
        for tasting in tastings {
            JournalPhotos.delete(tasting.photo)
        }
        tastings = []
        TastingStorage.save(tastings)
    }
}
