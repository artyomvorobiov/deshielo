import Foundation
import Observation
import WidgetKit

/// Личные данные: избранное, дневник готовки, заметки, меню на неделю и настройки.
/// Хранится в App Group, чтобы виджет «Кулинарный паспорт» видел дневник.
@MainActor
@Observable
final class ProfileStore {
    private(set) var profile: UserProfile

    init(profile: UserProfile? = nil) {
        self.profile = profile ?? ProfileStorage.load()
    }

    func reload() {
        profile = ProfileStorage.load()
    }

    // MARK: - Избранное

    func isFavorite(_ id: String) -> Bool { profile.favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if let index = profile.favorites.firstIndex(of: id) {
            profile.favorites.remove(at: index)
        } else {
            profile.favorites.insert(id, at: 0)
        }
        save(reloadWidgets: false)
    }

    // MARK: - Дневник готовки

    var cookedEntries: [CookedEntry] { profile.cooked.sorted { $0.date > $1.date } }

    func timesCooked(_ id: String) -> Int { profile.cooked.filter { $0.recipeID == id }.count }

    /// Запись в дневник. `title` нужен для рецептов не из каталога, `photo` — имя файла из JournalPhotos.
    func markCooked(_ id: String, title: String? = nil, rating: Int?, note: String?, photo: String? = nil) {
        profile.cooked.append(CookedEntry(recipeID: id, rating: rating, note: note?.nilIfBlank,
                                          title: title, photo: photo))
        save()
    }

    func deleteCooked(_ entry: CookedEntry) {
        profile.cooked.removeAll { $0.id == entry.id }
        JournalPhotos.delete(entry.photo)
        save()
    }

    // MARK: - Заметки к рецептам

    func note(for id: String) -> String { profile.notes[id] ?? "" }

    func setNote(_ text: String, for id: String) {
        profile.notes[id] = text.nilIfBlank
        save(reloadWidgets: false)
    }

    // MARK: - Меню на неделю

    func plan(on day: Date) -> [String] { profile.mealPlan[DayKey.make(day)] ?? [] }

    var plannedCount: Int {
        let today = DayKey.make(.now)
        return profile.mealPlan.filter { $0.key >= today }.reduce(0) { $0 + $1.value.count }
    }

    func addToPlan(_ id: String, on day: Date) {
        let key = DayKey.make(day)
        var list = profile.mealPlan[key] ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        profile.mealPlan[key] = list
        prunePastPlan()
        save(reloadWidgets: false)
    }

    func removeFromPlan(_ id: String, on day: Date) {
        let key = DayKey.make(day)
        var list = profile.mealPlan[key] ?? []
        list.removeAll { $0 == id }
        profile.mealPlan[key] = list.isEmpty ? nil : list
        save(reloadWidgets: false)
    }

    private func prunePastPlan() {
        let today = DayKey.make(.now)
        profile.mealPlan = profile.mealPlan.filter { $0.key >= today }
    }

    // MARK: - Холодильник

    var pantry: Set<String> { Set(profile.pantry) }

    func togglePantry(_ key: String) {
        if let index = profile.pantry.firstIndex(of: key) {
            profile.pantry.remove(at: index)
        } else {
            profile.pantry.append(key)
        }
        save(reloadWidgets: false)
    }

    func clearPantry() {
        profile.pantry = []
        save(reloadWidgets: false)
    }

    // MARK: - Недавно открытые

    func markViewed(_ id: String) {
        guard profile.recent.first != id else { return }
        profile.recent.removeAll { $0 == id }
        profile.recent.insert(id, at: 0)
        profile.recent = Array(profile.recent.prefix(12))
        save(reloadWidgets: false)
    }

    // MARK: - Настройки

    var speakSteps: Bool {
        get { profile.speakSteps }
        set {
            profile.speakSteps = newValue
            save(reloadWidgets: false)
        }
    }

    var includeStaples: Bool {
        get { profile.includeStaples }
        set {
            profile.includeStaples = newValue
            save(reloadWidgets: false)
        }
    }

    var preferredDeliveryID: String? {
        get { profile.preferredDeliveryID }
        set {
            profile.preferredDeliveryID = newValue
            save(reloadWidgets: false)
        }
    }

    func resetAll() {
        profile = UserProfile()
        JournalPhotos.deleteAll()
        save()
    }

    private func save(reloadWidgets: Bool = true) {
        ProfileStorage.save(profile)
        if reloadWidgets {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.passport)
        }
    }
}
