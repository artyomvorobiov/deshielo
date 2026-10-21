import CoreSpotlight
import UniformTypeIdentifiers

/// Рецепты в поиске iOS (Spotlight): найдите «борщ» прямо с домашнего экрана.
enum SpotlightIndexer {
    static func index(_ catalog: Catalog) {
        let items: [CSSearchableItem] = catalog.recipes.map { recipe -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = recipe.title
            attributes.contentDescription = recipe.summary
            attributes.keywords = [recipe.category.title] + recipe.ingredients.prefix(10).map(\.name)
            return CSSearchableItem(uniqueIdentifier: DeepLink.recipe(recipe.id).url.absoluteString,
                                    domainIdentifier: "recipes",
                                    attributeSet: attributes)
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    /// Ссылка на рецепт из результата поиска Spotlight.
    static func deepLink(from activity: NSUserActivity) -> DeepLink? {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let url = URL(string: identifier) else { return nil }
        return DeepLink(url: url)
    }
}
