import SwiftUI

/// Вкладка «Моё»: паспорт, избранное, дневник, меню, инструменты, настройки.
struct ProfileView: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile

    var body: some View {
        let passport = PassportSummary(profile: profile.profile, catalog: catalog)
        List {
            Section {
                NavigationLink(value: Route.passport) {
                    PassportSummaryCard(passport: passport)
                }
            }

            Section("Моя кухня") {
                NavigationLink(value: Route.favorites) {
                    CountRow(title: "Избранное", systemImage: "heart", count: profile.profile.favorites.count)
                }
                NavigationLink(value: Route.journal) {
                    CountRow(title: "Дневник готовки", systemImage: "book.closed", count: profile.profile.cooked.count)
                }
                NavigationLink(value: Route.mealPlan) {
                    CountRow(title: "Меню на неделю", systemImage: "calendar", count: profile.plannedCount)
                }
                NavigationLink(value: Route.fridge) {
                    CountRow(title: "Из холодильника", systemImage: "refrigerator", count: profile.profile.pantry.count)
                }
            }

            Section("Инструменты") {
                NavigationLink(value: Route.converter) {
                    Label("Конвертер мер и старинные меры", systemImage: "scalemass")
                }
                NavigationLink(value: Route.glossary) {
                    Label("Словарь шефа", systemImage: "character.book.closed")
                }
                NavigationLink(value: Route.timeMachine) {
                    Label("Машина времени", systemImage: "hourglass")
                }
                NavigationLink(value: Route.tasteMap) {
                    Label("Карта вкусов", systemImage: "map")
                }
            }

            Section {
                NavigationLink(value: Route.settings) {
                    Label("Настройки и о приложении", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Моё")
    }
}

private struct CountRow: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Карточка паспорта в профиле.
struct PassportSummaryCard: View {
    let passport: PassportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Кулинарный паспорт")
                        .font(.display(.title3))
                    Text("Готовьте блюда разных стран и эпох — собирайте штампы")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "globe.europe.africa.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 0) {
                PassportStat(value: "\(passport.countriesCount)/\(passport.totalCountries)", caption: "страны")
                PassportStat(value: "\(passport.eraIDs.count)/\(passport.totalEras)", caption: "эпохи")
                PassportStat(value: "\(passport.dishesCount)", caption: "блюда")
            }
            ProgressView(value: Double(passport.countriesCount), total: Double(max(passport.totalCountries, 1)))
                .tint(Theme.accent)
        }
        .padding(.vertical, 6)
    }
}

private struct PassportStat: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .serif).weight(.semibold))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Избранные рецепты сеткой.
struct FavoritesView: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile

    var body: some View {
        let recipes = profile.profile.favorites.compactMap { catalog.recipe($0) }
        Group {
            if recipes.isEmpty {
                ContentUnavailableView("Пока пусто",
                                       systemImage: "heart",
                                       description: Text("Нажмите ♡ на странице рецепта, чтобы сохранить его здесь."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                              spacing: 20) {
                        ForEach(recipes) { recipe in
                            NavigationLink(value: Route.recipe(recipe.id)) {
                                RecipeTile(recipe: recipe)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Избранное")
    }
}

/// Дневник готовки: что, когда, с какой оценкой.
struct JournalView: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile

    var body: some View {
        let entries = profile.cookedEntries
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Дневник пуст",
                                       systemImage: "book.closed",
                                       description: Text("Отмечайте приготовленные блюда — здесь появится история вашей кухни с оценками и заметками."))
            } else {
                List {
                    ForEach(entries) { entry in
                        if let recipe = catalog.recipe(entry.recipeID) {
                            NavigationLink(value: Route.recipe(recipe.id)) {
                                JournalRow(entry: entry, recipe: recipe)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            profile.deleteCooked(entries[offset])
                        }
                    }
                }
            }
        }
        .navigationTitle("Дневник готовки")
    }
}

private struct JournalRow: View {
    let entry: CookedEntry
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            DishArtwork(recipe: recipe, showsYear: false)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.headline)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let rating = entry.rating {
                    Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating)))
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                }
                if let note = entry.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
