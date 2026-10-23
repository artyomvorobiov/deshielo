import SwiftUI

/// Вкладка «Моё»: паспорт, избранное, дневник, меню, инструменты, настройки.
struct ProfileView: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile
    @Environment(CommunityStore.self) private var community

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

            if community.isConfigured {
                Section("Сообщество") {
                    NavigationLink(value: Route.communityAccount) {
                        Label(community.user.map { "Аккаунт: \($0.name)" } ?? "Войти в сообщество",
                              systemImage: "person.2")
                    }
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

/// Карточка паспорта: в профиле — с заголовком, на экране паспорта — только цифры.
struct PassportSummaryCard: View {
    let passport: PassportSummary
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
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
            }
            HStack(spacing: 0) {
                PassportStat(value: "\(passport.countriesCount)/\(passport.totalCountries)", caption: "страны")
                PassportStat(value: "\(passport.eraIDs.count)/\(passport.totalEras)", caption: "эпохи")
                PassportStat(value: "\(passport.dishesCount)",
                             caption: RussianPlural.form(passport.dishesCount, "блюдо", "блюда", "блюд"))
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

/// Дневник готовки: что, когда, с какой оценкой и как выглядело.
struct JournalView: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile

    @State private var viewer: JournalPhotoItem?

    /// Запись дневника и то, куда она ведёт: рецепт каталога или сообщества.
    private struct Item: Identifiable {
        let entry: CookedEntry
        let recipe: Recipe?
        let route: Route?

        var id: UUID { entry.id }
        var title: String { recipe?.title ?? entry.title ?? "Рецепт" }
    }

    private var items: [Item] {
        profile.cookedEntries.compactMap { entry -> Item? in
            if let recipe = catalog.recipe(entry.recipeID) {
                return Item(entry: entry, recipe: recipe, route: .recipe(recipe.id))
            }
            if entry.recipeID.hasPrefix(Recipe.communityPrefix) {
                let id = String(entry.recipeID.dropFirst(Recipe.communityPrefix.count))
                return Item(entry: entry, recipe: nil, route: .communityRecipe(id))
            }
            return nil
        }
    }

    var body: some View {
        let items = items
        Group {
            if items.isEmpty {
                ContentUnavailableView("Дневник пуст",
                                       systemImage: "book.closed",
                                       description: Text("Отмечайте приготовленные блюда — здесь появится история вашей кухни с оценками, заметками и фото."))
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink(value: item.route) {
                            JournalRow(entry: item.entry, recipe: item.recipe, title: item.title) { name in
                                viewer = JournalPhotoItem(name: name)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            profile.deleteCooked(items[offset].entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("Дневник готовки")
        .fullScreenCover(item: $viewer) { item in
            JournalPhotoViewer(name: item.name)
        }
    }
}

private struct JournalPhotoItem: Identifiable {
    let name: String

    var id: String { name }
}

private struct JournalRow: View {
    let entry: CookedEntry
    let recipe: Recipe?
    let title: String
    let onPhoto: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            cover
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
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

    @ViewBuilder
    private var cover: some View {
        if let name = entry.photo, let image = JournalPhotos.image(named: name) {
            Button {
                onPhoto(name)
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Фото результата")
        } else if let recipe {
            DishArtwork(recipe: recipe, showsYear: false)
        } else {
            DishArtwork(recipe: .artworkPlaceholder(id: entry.recipeID, palette: ["#B4532A", "#F3E3B5", "#5E7F37"]),
                        showsYear: false)
        }
    }
}

/// Фото из дневника на весь экран.
private struct JournalPhotoViewer: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = JournalPhotos.image(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
            .accessibilityLabel("Закрыть")
        }
    }
}
