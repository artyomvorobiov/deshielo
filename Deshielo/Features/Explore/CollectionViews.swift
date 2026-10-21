import SwiftUI

/// Коллекция: шапка с описанием и список рецептов.
struct CollectionDetailView: View {
    let collection: RecipeCollection

    @Environment(\.catalog) private var catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if collection.showsCountries {
                    CountriesGrid()
                } else if collection.id == "chefs" {
                    chefsList
                } else {
                    recipesList(catalog.recipes(inCollection: collection.id))
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: collection.symbol)
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text(collection.title)
                .font(.display(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
            Text(collection.description)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            if collection.showsCountries {
                NavigationLink(value: Route.tasteMap) {
                    Label("Открыть карту вкусов", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.2), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: collection.palette.prefix(2).map(Color.init(hex:)),
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        )
    }

    private var chefsList: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(catalog.chefsWithRecipes) { chef in
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink(value: Route.chef(chef.id)) {
                        ChefHeader(chef: chef, compact: true)
                    }
                    .buttonStyle(.plain)
                    recipesList(catalog.recipes(byChef: chef.id))
                }
            }
        }
    }

    private func recipesList(_ recipes: [Recipe]) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(recipes) { recipe in
                NavigationLink(value: Route.recipe(recipe.id)) {
                    RecipeRow(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Шапка шефа: монограмма, имя, годы.
struct ChefHeader: View {
    let chef: Chef
    var compact = false

    var body: some View {
        HStack(spacing: 14) {
            MonogramView(text: chef.initials, palette: ["#3B3530", "#B4532A"])
                .frame(width: compact ? 48 : 72, height: compact ? 48 : 72)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(chef.name)
                    .font(.display(compact ? .headline : .title2))
                    .foregroundStyle(.primary)
                Text("\(chef.role) · \(chef.years)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if compact {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ChefDetailView: View {
    let chef: Chef

    @Environment(\.catalog) private var catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ChefHeader(chef: chef)
                if let country = catalog.country(chef.country) {
                    Text("\(country.flag) \(country.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(chef.bio)
                    .font(.system(.body, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                SectionHeader(title: "Рецепты")
                LazyVStack(spacing: 16) {
                    ForEach(catalog.recipes(byChef: chef.id)) { recipe in
                        NavigationLink(value: Route.recipe(recipe.id)) {
                            RecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Рецепты — домашние адаптации по мотивам блюд шефа, написанные редакцией Deshielo.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(chef.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Сетка стран с флагами и отметками паспорта.
struct CountriesGrid: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile

    var body: some View {
        let passport = PassportSummary(profile: profile.profile, catalog: catalog)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
            ForEach(catalog.countriesWithRecipes) { country in
                NavigationLink(value: Route.country(country.code)) {
                    VStack(spacing: 6) {
                        Text(country.flag)
                            .font(.system(size: 40))
                        Text(country.name)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(RussianPlural.phrase(catalog.recipes(inCountry: country.code).count,
                                                  "рецепт", "рецепта", "рецептов"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if passport.stamps[country.code] != nil {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Theme.herb)
                                .padding(8)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CountryDetailView: View {
    let country: Country

    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile

    var body: some View {
        let stamp = PassportSummary(profile: profile.profile, catalog: catalog).stamps[country.code]
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(country.flag)
                    .font(.system(size: 64))
                Text(country.name)
                    .font(.display(.largeTitle, weight: .bold))
                Text(country.cuisine)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let stamp {
                    Label("Штамп в паспорте с \(stamp.formatted(date: .long, time: .omitted))",
                          systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.herb)
                } else {
                    Label("Приготовьте любое блюдо, чтобы получить штамп в кулинарный паспорт",
                          systemImage: "seal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 16) {
                    ForEach(catalog.recipes(inCountry: country.code)) { recipe in
                        NavigationLink(value: Route.recipe(recipe.id)) {
                            RecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(country.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
