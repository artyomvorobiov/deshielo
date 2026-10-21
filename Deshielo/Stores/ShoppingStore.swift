import Foundation
import Observation
import WidgetKit

/// Список покупок. Хранится в App Group: виджет показывает его и умеет отмечать покупки.
@MainActor
@Observable
final class ShoppingStore {
    private(set) var list: ShoppingList

    init(list: ShoppingList? = nil) {
        self.list = list ?? ShoppingListStorage.load()
    }

    var items: [ShoppingItem] { list.items }
    var uncheckedCount: Int { list.items.filter { !$0.isChecked }.count }
    var checkedCount: Int { list.items.filter(\.isChecked).count }

    /// Перечитать файл — например, после того как покупку отметили в виджете.
    func reload() {
        list = ShoppingListStorage.load()
    }

    /// Добавляет ингредиенты рецепта с учётом порций. Одинаковые продукты складываются.
    @discardableResult
    func add(recipe: Recipe, scale: Double, catalog: Catalog, includeStaples: Bool,
             onlyIndices: Set<Int>? = nil) -> Int {
        let newItems = ShoppingMerger.items(for: recipe, scale: scale, catalog: catalog,
                                            includeStaples: includeStaples, onlyIndices: onlyIndices)
        let count = ShoppingMerger.merge(newItems, into: &list.items)
        save()
        return count
    }

    /// Добавляет продукты по ключам (например, недостающие в «Из холодильника»).
    @discardableResult
    func add(keys: [String], recipeID: String?, catalog: Catalog) -> Int {
        let newItems = keys.compactMap { key -> ShoppingItem? in
            guard let pantryItem = catalog.pantryItem(key) else { return nil }
            return ShoppingItem(name: pantryItem.name, key: key, aisle: pantryItem.category,
                                recipeIDs: recipeID.map { [$0] } ?? [])
        }
        let count = ShoppingMerger.merge(newItems, into: &list.items)
        save()
        return count
    }

    func addCustom(_ name: String, catalog: Catalog) {
        guard let trimmed = name.nilIfBlank else { return }
        let normalized = trimmed.searchNormalized
        let match = catalog.pantry.first { $0.name.searchNormalized == normalized }
            ?? catalog.pantry.first { normalized.contains($0.name.searchNormalized) }
        let item = ShoppingItem(name: trimmed, key: match?.key, aisle: match?.category ?? .other)
        ShoppingMerger.merge([item], into: &list.items)
        save()
    }

    func toggle(_ item: ShoppingItem) {
        guard let index = list.items.firstIndex(where: { $0.id == item.id }) else { return }
        list.items[index].isChecked.toggle()
        save()
    }

    func delete(_ ids: Set<UUID>) {
        list.items.removeAll { ids.contains($0.id) }
        save()
    }

    func clearChecked() {
        list.items.removeAll(where: \.isChecked)
        save()
    }

    func clearAll() {
        list.items.removeAll()
        save()
    }

    /// Текст для «Поделиться»: по отделам, с количествами.
    func shareText() -> String {
        var lines = ["Список покупок — Deshielo", ""]
        for aisle in Aisle.allCases {
            let aisleItems = list.items.filter { $0.aisle == aisle && !$0.isChecked }
            guard !aisleItems.isEmpty else { continue }
            lines.append("\(aisle.emoji) \(aisle.title)")
            for item in aisleItems {
                let amount = item.amountText
                lines.append(amount.isEmpty ? "• \(item.name)" : "• \(item.name) — \(amount)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        ShoppingListStorage.save(list)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.shoppingList)
    }
}

/// Логика превращения ингредиентов в строки списка и слияния одинаковых продуктов.
enum ShoppingMerger {
    static func items(for recipe: Recipe, scale: Double, catalog: Catalog,
                      includeStaples: Bool, onlyIndices: Set<Int>?) -> [ShoppingItem] {
        var result: [ShoppingItem] = []
        for (index, ingredient) in recipe.ingredients.enumerated() {
            if let onlyIndices {
                guard onlyIndices.contains(index) else { continue }
            } else if ingredient.optional {
                continue
            }
            let pantryItem = catalog.pantryItem(ingredient.key)
            if ingredient.key == "water" { continue }
            if pantryItem?.staple == true && !includeStaples { continue }

            let measure = ingredient.measureUnit
            let amount: Double? = measure == .toTaste ? nil : ingredient.amount.map { $0 * scale }
            result.append(ShoppingItem(name: pantryItem?.name ?? ingredient.name,
                                       amount: amount,
                                       unit: amount == nil ? nil : ingredient.unit,
                                       key: ingredient.key,
                                       aisle: pantryItem?.category ?? .other,
                                       recipeIDs: [recipe.id]))
        }
        return result
    }

    /// Сливает новые строки со списком. Возвращает число обработанных строк.
    @discardableResult
    static func merge(_ newItems: [ShoppingItem], into list: inout [ShoppingItem]) -> Int {
        for item in newItems {
            if let index = list.firstIndex(where: { canMerge($0, item) }) {
                list[index] = combined(list[index], item)
            } else {
                list.append(item)
            }
        }
        return newItems.count
    }

    static func canMerge(_ existing: ShoppingItem, _ new: ShoppingItem) -> Bool {
        guard !existing.isChecked else { return false }
        let sameProduct: Bool
        if let key = existing.key, let newKey = new.key {
            sameProduct = key == newKey
        } else {
            sameProduct = existing.name.searchNormalized == new.name.searchNormalized
        }
        guard sameProduct else { return false }
        guard existing.amount != nil, new.amount != nil else { return true }
        if existing.unit == new.unit { return true }
        guard let a = existing.unit.flatMap(MeasureUnit.init(rawValue:)),
              let b = new.unit.flatMap(MeasureUnit.init(rawValue:)) else { return false }
        return a.kind == b.kind && (a.kind == .mass || a.kind == .volume)
    }

    static func combined(_ existing: ShoppingItem, _ new: ShoppingItem) -> ShoppingItem {
        var result = existing
        result.recipeIDs += new.recipeIDs.filter { !existing.recipeIDs.contains($0) }
        guard let newAmount = new.amount else { return result }
        guard let oldAmount = existing.amount else {
            result.amount = newAmount
            result.unit = new.unit
            return result
        }
        if existing.unit == new.unit {
            result.amount = oldAmount + newAmount
        } else if let a = existing.unit.flatMap(MeasureUnit.init(rawValue:)),
                  let b = new.unit.flatMap(MeasureUnit.init(rawValue:)) {
            result.amount = oldAmount * a.baseFactor + newAmount * b.baseFactor
            result.unit = a.kind == .mass ? MeasureUnit.g.rawValue : MeasureUnit.ml.rawValue
        }
        return result
    }
}
