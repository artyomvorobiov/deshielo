import AppIntents
import WidgetKit

/// Отметка покупки прямо из виджета — без открытия приложения.
struct ToggleShoppingItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить покупку"
    static let description = IntentDescription("Отмечает продукт в списке покупок как купленный.")
    static let isDiscoverable = false

    @Parameter(title: "Продукт")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        ShoppingListStorage.toggle(itemID: itemID)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.shoppingList)
        return .result()
    }
}
