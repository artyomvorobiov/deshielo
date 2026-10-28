import SwiftUI

/// Винная и чайная карта: стили и сорта вина, регионы, чаи, карта и дегустационный дневник.
struct DrinksView: View {
    @Environment(\.drinks) private var drinks
    @Environment(\.catalog) private var catalog
    @Environment(TastingStore.self) private var tastings

    @State private var section: Tasting.Kind = DrinksConfig.showsWine ? .wine : .tea
    @State private var query = ""

    private var showsWine: Bool { DrinksConfig.showsWine }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let text = query.nilIfBlank {
                    DrinkSearchResults(results: drinks.search(text, includesWine: showsWine), query: text)
                } else {
                    if showsWine {
                        Picker("Раздел", selection: $section) {
                            ForEach(Tasting.Kind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                    }
                    if showsWine && section == .wine {
                        wineContent
                    } else {
                        teaContent
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle(showsWine ? "Вино и чай" : "Чайная карта")
        .searchable(text: $query, prompt: Text(showsWine ? "Сорт, регион, чай или аромат" : "Чай, страна или аромат"))
        .animation(.default, value: section)
    }

    // MARK: - Вино

    private var wineContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            DrinkShelf(title: "Стили", subtitle: "Какое вино к какому блюду") {
                ForEach(drinks.wine.styles) { style in
                    NavigationLink(value: Route.wineStyle(style.id)) {
                        DrinkTile(title: style.name, subtitle: style.serving) {
                            DrinkArtwork(style: style)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            grapeShelf(.red, title: "Красные сорта")
            grapeShelf(.white, title: "Белые сорта")
            regionGrid
            links(for: .wine)
            Text("Раздел о вине — для совершеннолетних. Чрезмерное употребление алкоголя вредит вашему здоровью.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
        }
    }

    private func grapeShelf(_ color: WineColor, title: String) -> some View {
        let grapes = drinks.grapes(color)
        return DrinkShelf(title: title, subtitle: RussianPlural.phrase(grapes.count, "сорт", "сорта", "сортов")) {
            ForEach(grapes) { grape in
                NavigationLink(value: Route.grape(grape.id)) {
                    DrinkTile(title: grape.name, subtitle: grape.aromas.prefix(3).joined(separator: ", ")) {
                        DrinkArtwork(grape: grape)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var regionGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Регионы",
                          subtitle: RussianPlural.phrase(drinks.wine.regions.count, "регион", "региона", "регионов"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(drinks.wine.regions) { region in
                    NavigationLink(value: Route.wineRegion(region.id)) {
                        HStack(spacing: 10) {
                            Text(CountryName.flag(region.country))
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(region.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(CountryName.name(region.country, catalog: catalog))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Чай

    private var teaContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            DrinkShelf(title: "Типы чая", subtitle: "От белого до пуэра — по степени окисления") {
                ForEach(drinks.tea.types) { type in
                    NavigationLink(value: Route.teaType(type.id)) {
                        DrinkTile(title: type.name, subtitle: "Окисление: \(type.oxidation.lowercasedFirst)") {
                            DrinkArtwork(teaType: type)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(drinks.tea.types) { type in
                let teas = drinks.teas(ofType: type.id)
                if !teas.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: type.name,
                                      subtitle: "\(type.brewing.temperature) °C · \(type.brewing.ratioText)")
                        ForEach(teas) { tea in
                            NavigationLink(value: Route.tea(tea.id)) {
                                DrinkRow(title: tea.name, subtitle: tea.origin,
                                         trailing: CountryName.flag(tea.country)) {
                                    DrinkArtwork(tea: tea)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            links(for: .tea)
        }
    }

    // MARK: - Карта и дневник

    private func links(for kind: Tasting.Kind) -> some View {
        let count = tastings.tastings(of: kind).count
        return VStack(spacing: 12) {
            DrinkLinkCard(title: kind == .wine ? "Карта вин и чая" : "Карта чая",
                          subtitle: kind == .wine ? "Где растут сорта и откуда родом чаи" : "Откуда родом чаи и травы",
                          systemImage: "map", route: .drinkMap)
            DrinkLinkCard(title: "Дегустационный дневник",
                          subtitle: count > 0
                              ? RussianPlural.phrase(count, "запись", "записи", "записей")
                              : "Сфотографируйте этикетку — приложение прочитает название",
                          systemImage: "book.closed", route: .tastings)
        }
        .padding(.horizontal, 20)
    }
}

/// Результаты поиска по винной и чайной карте.
private struct DrinkSearchResults: View {
    let results: DrinkCatalog.SearchResults
    let query: String

    @Environment(\.catalog) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            ForEach(results.styles) { style in
                NavigationLink(value: Route.wineStyle(style.id)) {
                    DrinkRow(title: style.name, subtitle: "Стиль вина · \(style.serving)") {
                        DrinkArtwork(style: style)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(results.grapes) { grape in
                NavigationLink(value: Route.grape(grape.id)) {
                    DrinkRow(title: grape.name, subtitle: "\(grape.color.title) · \(grape.original)") {
                        DrinkArtwork(grape: grape)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(results.regions) { region in
                NavigationLink(value: Route.wineRegion(region.id)) {
                    DrinkRow(title: region.name,
                             subtitle: "Винодельческий регион · \(CountryName.name(region.country, catalog: catalog))") {
                        FlagBadge(code: region.country)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(results.teaTypes) { type in
                NavigationLink(value: Route.teaType(type.id)) {
                    DrinkRow(title: type.name, subtitle: "Окисление: \(type.oxidation.lowercasedFirst)") {
                        DrinkArtwork(teaType: type)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(results.teas) { tea in
                NavigationLink(value: Route.tea(tea.id)) {
                    DrinkRow(title: tea.name, subtitle: tea.origin, trailing: CountryName.flag(tea.country)) {
                        DrinkArtwork(tea: tea)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// Флаг страны на подложке — вместо иллюстрации у регионов.
struct FlagBadge: View {
    let code: String

    var body: some View {
        ZStack {
            Theme.surfaceSecondary
            Text(CountryName.flag(code))
                .font(.system(size: 30))
        }
    }
}
