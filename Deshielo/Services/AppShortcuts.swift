import AppIntents

/// Команды для Siri и приложения «Команды»: «Рецепт дня в Deshielo».
struct OpenRecipeOfTheDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Рецепт дня"
    static let description = IntentDescription("Открывает рецепт дня в Deshielo.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.open(.recipeOfTheDay)
        return .result()
    }
}

struct OpenShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "Список покупок"
    static let description = IntentDescription("Открывает список покупок в Deshielo.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.open(.shopping)
        return .result()
    }
}

struct SurpriseRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Удиви меня"
    static let description = IntentDescription("Открывает случайный необычный рецепт.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let recipe = Catalog.bundled.recipes.randomElement() {
            Router.shared.open(.recipe(recipe.id))
        }
        return .result()
    }
}

struct DeshieloShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenRecipeOfTheDayIntent(),
                    phrases: ["Рецепт дня в \(.applicationName)",
                              "Что приготовить в \(.applicationName)"],
                    shortTitle: "Рецепт дня",
                    systemImageName: "fork.knife")
        AppShortcut(intent: OpenShoppingListIntent(),
                    phrases: ["Список покупок в \(.applicationName)",
                              "Покупки в \(.applicationName)"],
                    shortTitle: "Покупки",
                    systemImageName: "cart")
        AppShortcut(intent: SurpriseRecipeIntent(),
                    phrases: ["Удиви меня в \(.applicationName)"],
                    shortTitle: "Удиви меня",
                    systemImageName: "sparkles")
    }
}
