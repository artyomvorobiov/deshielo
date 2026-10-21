import SwiftUI

/// Совпадение рецепта с продуктами, которые есть дома.
struct FridgeMatch: Identifiable {
    let recipe: Recipe
    let have: [String]
    let missing: [String]

    var id: String { recipe.id }
    var ratio: Double {
        let total = have.count + missing.count
        return total == 0 ? 0 : Double(have.count) / Double(total)
    }
}

enum FridgeMatcher {
    /// Базовые продукты, которые считаются «всегда есть дома».
    static func isStaple(_ key: String, catalog: Catalog) -> Bool {
        catalog.pantryItem(key)?.staple == true
    }

    /// Рецепты, отсортированные по доле имеющихся продуктов.
    static func matches(pantry: Set<String>, catalog: Catalog) -> [FridgeMatch] {
        guard !pantry.isEmpty else { return [] }
        var result: [FridgeMatch] = []
        for recipe in catalog.recipes {
            var required: [String] = []
            // Необязательное и то, что «для подачи», не мешает начать готовить.
            for ingredient in recipe.ingredients where !ingredient.optional && ingredient.group != "Для подачи" {
                guard let key = ingredient.key, !isStaple(key, catalog: catalog), !required.contains(key) else { continue }
                required.append(key)
            }
            let have = required.filter { pantry.contains($0) }
            guard !have.isEmpty else { continue }
            let missing = required.filter { !pantry.contains($0) }
            result.append(FridgeMatch(recipe: recipe, have: have, missing: missing))
        }
        return result.sorted {
            if $0.missing.count != $1.missing.count { return $0.missing.count < $1.missing.count }
            return $0.ratio > $1.ratio
        }
    }
}

/// «Из холодильника»: отметьте, что есть дома, — и получите рецепты.
struct FridgeView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case products = "Продукты"
        case recipes = "Рецепты"
        var id: String { rawValue }
    }

    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile
    @Environment(ShoppingStore.self) private var shopping

    @State private var mode: Mode = .products
    @State private var query = ""
    @State private var toast: String?

    var body: some View {
        let pantry = profile.pantry
        let matches = FridgeMatcher.matches(pantry: pantry, catalog: catalog)
        VStack(spacing: 0) {
            Picker("Режим", selection: $mode) {
                Text("Что есть дома · \(pantry.count)").tag(Mode.products)
                Text("Можно приготовить · \(matches.count)").tag(Mode.recipes)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            switch mode {
            case .products:
                productsList(pantry: pantry)
            case .recipes:
                recipesList(matches)
            }
        }
        .screenBackground()
        .navigationTitle("Из холодильника")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !pantry.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") { profile.clearPantry() }
                }
            }
        }
        .toast($toast)
    }

    private func productsList(pantry: Set<String>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TextField("Найти продукт", text: $query)
                    .textFieldStyle(.roundedBorder)
                ForEach(Aisle.allCases) { aisle in
                    let items = catalog.pantry.filter { item in
                        item.category == aisle && item.fridge && !item.staple
                            && (query.isEmpty || item.name.searchNormalized.contains(query.searchNormalized))
                    }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(aisle.emoji) \(aisle.title)")
                                .font(.headline)
                            FlowLayout(spacing: 8) {
                                ForEach(items) { item in
                                    Chip(title: "\(item.emoji) \(item.name)", isSelected: pantry.contains(item.key)) {
                                        profile.togglePantry(item.key)
                                    }
                                }
                            }
                        }
                    }
                }
                Text("Соль, перец, сахар, масло и вода считаются базовыми — они есть почти в каждом доме.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .sensoryFeedback(.selection, trigger: pantry)
    }

    @ViewBuilder
    private func recipesList(_ matches: [FridgeMatch]) -> some View {
        if matches.isEmpty {
            ContentUnavailableView("Отметьте продукты",
                                   systemImage: "refrigerator",
                                   description: Text("Выберите, что есть у вас дома, — и мы подберём рецепты, для которых не хватает меньше всего."))
        } else {
            List(matches) { match in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink(value: Route.recipe(match.recipe.id)) {
                        RecipeRow(recipe: match.recipe, detail: matchText(match))
                    }
                    if !match.missing.isEmpty {
                        Button {
                            let count = shopping.add(keys: match.missing, recipeID: match.recipe.id, catalog: catalog)
                            toast = "В покупках: +\(RussianPlural.phrase(count, "продукт", "продукта", "продуктов"))"
                        } label: {
                            Label("Докупить: \(match.missing.compactMap { catalog.pantryItem($0)?.name.lowercased() }.joined(separator: ", "))",
                                  systemImage: "cart.badge.plus")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(2)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
    }

    private func matchText(_ match: FridgeMatch) -> String {
        if match.missing.isEmpty {
            return "Есть всё необходимое"
        }
        return "Есть \(match.have.count) из \(match.have.count + match.missing.count) продуктов"
    }
}
