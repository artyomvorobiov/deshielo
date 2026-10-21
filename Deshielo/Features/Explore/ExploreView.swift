import SwiftUI

/// Фильтры каталога.
struct RecipeFilter: Equatable {
    var category: RecipeCategory?
    var maxMinutes: Int?
    var difficulty: Int?
    var diet: Diet?

    var isEmpty: Bool { category == nil && maxMinutes == nil && difficulty == nil && diet == nil }

    func matches(_ recipe: Recipe) -> Bool {
        if let category, recipe.category != category { return false }
        if let maxMinutes, recipe.activeMinutes > maxMinutes { return false }
        if let difficulty, recipe.difficulty != difficulty { return false }
        if let diet, !recipe.diets.contains(diet) { return false }
        return true
    }
}

/// Вкладка «Рецепты»: поиск, инструменты, коллекции, фильтры.
struct ExploreView: View {
    @Environment(\.catalog) private var catalog

    @State private var query = ""
    @State private var filter = RecipeFilter()

    private var results: [Recipe] {
        catalog.search(query).filter(filter.matches)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if query.isEmpty && filter.isEmpty {
                    ToolsRow()
                    collections
                }
                FilterBar(filter: $filter)
                resultsSection
            }
            .padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle("Рецепты")
        .searchable(text: $query, prompt: "Блюдо, продукт, страна или шеф")
        .animation(.default, value: filter)
    }

    private var collections: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Коллекции")
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(catalog.collections) { collection in
                        NavigationLink(value: Route.collection(collection.id)) {
                            CollectionTile(collection: collection,
                                           count: catalog.recipes(inCollection: collection.id).count)
                                .frame(width: 170)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        let list = results
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: query.isEmpty && filter.isEmpty ? "Все рецепты" : "Найдено",
                          subtitle: RussianPlural.phrase(list.count, "рецепт", "рецепта", "рецептов"))
            if list.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(list) { recipe in
                        NavigationLink(value: Route.recipe(recipe.id)) {
                            RecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

/// Быстрые инструменты: холодильник, карта, машина времени, конвертер, словарь.
struct ToolsRow: View {
    private struct Tool: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let route: Route
    }

    private let tools = [
        Tool(id: "fridge", title: "Из холодильника", symbol: "refrigerator", route: .fridge),
        Tool(id: "map", title: "Карта вкусов", symbol: "map", route: .tasteMap),
        Tool(id: "time", title: "Машина времени", symbol: "hourglass", route: .timeMachine),
        Tool(id: "converter", title: "Конвертер мер", symbol: "scalemass", route: .converter),
        Tool(id: "glossary", title: "Словарь шефа", symbol: "character.book.closed", route: .glossary)
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(tools) { tool in
                    NavigationLink(value: tool.route) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: tool.symbol)
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                            Text(tool.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(14)
                        .frame(width: 128, height: 108, alignment: .topLeading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// Панель фильтров в виде меню-капсул.
struct FilterBar: View {
    @Binding var filter: RecipeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Любые блюда") { filter.category = nil }
                    ForEach(RecipeCategory.allCases) { category in
                        Button(category.title) { filter.category = category }
                    }
                } label: {
                    FilterLabel(title: filter.category?.title ?? "Блюдо", isActive: filter.category != nil)
                }

                Menu {
                    Button("Любое время") { filter.maxMinutes = nil }
                    Button("До 30 минут") { filter.maxMinutes = 30 }
                    Button("До 1 часа") { filter.maxMinutes = 60 }
                    Button("До 2 часов") { filter.maxMinutes = 120 }
                } label: {
                    FilterLabel(title: filter.maxMinutes.map { "До \(DurationText.short(minutes: $0))" } ?? "Время",
                                isActive: filter.maxMinutes != nil)
                }

                Menu {
                    Button("Любая сложность") { filter.difficulty = nil }
                    Button("Просто") { filter.difficulty = 1 }
                    Button("Средне") { filter.difficulty = 2 }
                    Button("Сложно") { filter.difficulty = 3 }
                } label: {
                    FilterLabel(title: difficultyTitle, isActive: filter.difficulty != nil)
                }

                Menu {
                    Button("Любой рацион") { filter.diet = nil }
                    ForEach(Diet.allCases) { diet in
                        Button(diet.title) { filter.diet = diet }
                    }
                } label: {
                    FilterLabel(title: filter.diet?.title ?? "Рацион", isActive: filter.diet != nil)
                }

                if !filter.isEmpty {
                    Button {
                        filter = RecipeFilter()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .padding(9)
                            .background(Theme.surfaceSecondary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Сбросить фильтры")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var difficultyTitle: String {
        switch filter.difficulty {
        case 1?: "Просто"
        case 2?: "Средне"
        case 3?: "Сложно"
        default: "Сложность"
        }
    }
}

private struct FilterLabel: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isActive ? Theme.accent : Theme.surfaceSecondary, in: Capsule())
        .foregroundStyle(isActive ? Color.white : Color.primary)
    }
}

/// Все рецепты одним списком.
struct AllRecipesView: View {
    @Environment(\.catalog) private var catalog

    var body: some View {
        List(catalog.recipes) { recipe in
            NavigationLink(value: Route.recipe(recipe.id)) {
                RecipeRow(recipe: recipe)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Все рецепты")
    }
}
