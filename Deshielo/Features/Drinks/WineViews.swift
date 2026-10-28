import SwiftUI

/// Стиль вина: как подавать, какие сорта и к каким блюдам.
struct WineStyleView: View {
    let style: WineStyle

    @Environment(\.drinks) private var drinks
    @Environment(\.pairings) private var pairings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DrinkHero(eyebrow: "Стиль вина", title: style.name, summary: style.summary) {
                    DrinkArtwork(style: style)
                }
                Text(style.description)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                ServingCard(serving: style.serving, glass: style.glass)
                DrinkRecipesShelf(title: "Что приготовить", note: style.pairing.note,
                                  recipes: pairings.recipes(forStyle: style))
                let grapes = drinks.grapes(inStyle: style.id)
                if !grapes.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Сорта", subtitle: "Из чего делают такие вина")
                        ForEach(grapes) { grape in
                            NavigationLink(value: Route.grape(grape.id)) {
                                DrinkRow(title: grape.name, subtitle: grape.summary) {
                                    DrinkArtwork(grape: grape)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(style.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Температура подачи и бокал.
private struct ServingCard: View {
    let serving: String
    let glass: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Подавать")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(serving)
                        .font(.subheadline.weight(.semibold))
                }
            } icon: {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(Theme.accent)
            }
            Divider()
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Бокал")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(glass)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "wineglass")
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Сорт винограда: характер вина, ароматы, история, регионы и блюда.
struct GrapeView: View {
    let grape: Grape

    @Environment(\.drinks) private var drinks
    @Environment(\.pairings) private var pairings
    @Environment(\.catalog) private var catalog
    @Environment(TastingStore.self) private var tastings

    @State private var newTasting: Tasting?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DrinkHero(eyebrow: grape.color.title, title: grape.name, original: grape.original,
                          summary: grape.summary) {
                    DrinkArtwork(grape: grape)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ScaleBar(title: "Тело", value: grape.body)
                    ScaleBar(title: "Кислотность", value: grape.acidity)
                    ScaleBar(title: "Танины", value: grape.tannin)
                }
                .card()
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Ароматы")
                    AromaCloud(aromas: grape.aromas)
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "История")
                    Text(grape.story)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                styles
                DrinkRecipesShelf(title: "Что приготовить", note: nil, recipes: pairings.recipes(forGrape: grape))
                regions
                VStack(spacing: 12) {
                    VivinoButton(title: "Найти вина в Vivino", query: grape.vivino)
                    Button {
                        newTasting = Tasting(kind: .wine, name: "", styleID: grape.styles.first, grapeID: grape.id)
                    } label: {
                        Label("Записать дегустацию", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
                TastingList(title: "Мои дегустации", tastings: tastings.tastings(grape: grape.id))
                Text("Vivino — сторонний сервис: поиск откроется на их сайте или в приложении. Оценки и цены Vivino Deshielo не показывает.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(grape.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $newTasting) { tasting in
            TastingEditorView(tasting: tasting, isNew: true)
        }
    }

    @ViewBuilder
    private var styles: some View {
        let list = drinks.styles(of: grape)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Стили")
                FlowLayout(spacing: 8) {
                    ForEach(list) { style in
                        NavigationLink(value: Route.wineStyle(style.id)) {
                            Label(style.name, systemImage: "wineglass")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.surfaceSecondary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var regions: some View {
        let list = drinks.regions(of: grape)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Где растёт")
                ForEach(list) { region in
                    NavigationLink(value: Route.wineRegion(region.id)) {
                        DrinkRow(title: region.name, subtitle: CountryName.name(region.country, catalog: catalog),
                                 trailing: CountryName.flag(region.country)) {
                            FlagBadge(code: region.country)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Винодельческий регион: где он, чем знаменит, какие сорта и что там едят.
struct WineRegionView: View {
    let region: WineRegion

    @Environment(\.drinks) private var drinks
    @Environment(\.catalog) private var catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PlaceMap(title: region.name, latitude: region.lat, longitude: region.lon, symbol: "wineglass")
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(CountryName.flag(region.country)) \(CountryName.name(region.country, catalog: catalog))".uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.accent)
                    Text(region.name)
                        .font(.display(.largeTitle, weight: .bold))
                    if region.original != region.name {
                        Text(region.original)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(region.summary)
                    .font(.system(.body, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                Text(region.story)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Сорта региона")
                    ForEach(drinks.grapes(of: region)) { grape in
                        NavigationLink(value: Route.grape(grape.id)) {
                            DrinkRow(title: grape.name, subtitle: grape.aromas.prefix(3).joined(separator: ", ")) {
                                DrinkArtwork(grape: grape)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                DrinkRecipesShelf(title: "Кухня этих мест", note: "Местное вино лучше всего звучит с местной едой.",
                                  recipes: Array(catalog.recipes(inCountry: region.country).prefix(10)))
                VivinoButton(title: "Вина региона в Vivino", query: region.vivino)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(region.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
