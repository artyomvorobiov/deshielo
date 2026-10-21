import MapKit
import SwiftUI

/// Карта вкусов: флаги стран с рецептами; отмеченные в паспорте — с зелёной обводкой.
struct TasteMapView: View {
    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile

    @State private var selected: Country?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        let stamps = PassportSummary(profile: profile.profile, catalog: catalog).stamps
        Map(position: $position) {
            ForEach(catalog.countriesWithRecipes) { country in
                Annotation(country.name,
                           coordinate: CLLocationCoordinate2D(latitude: country.lat, longitude: country.lon)) {
                    Button {
                        withAnimation(.snappy) { selected = country }
                    } label: {
                        Text(country.flag)
                            .font(.system(size: selected == country ? 34 : 26))
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                            .overlay {
                                Circle().stroke(stamps[country.code] != nil ? Theme.herb : Color.clear, lineWidth: 2.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(country.name)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .bottom) {
            if let selected {
                CountryMapCard(country: selected, stamped: stamps[selected.code] != nil) {
                    withAnimation(.snappy) { self.selected = nil }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Нажмите на флаг, чтобы увидеть блюда страны")
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle("Карта вкусов")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CountryMapCard: View {
    let country: Country
    let stamped: Bool
    let onClose: () -> Void

    @Environment(\.catalog) private var catalog

    var body: some View {
        let recipes = catalog.recipes(inCountry: country.code)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(country.flag).font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(country.name).font(.display(.title3))
                    Text(stamped ? "Штамп в паспорте получен" : RussianPlural.phrase(recipes.count, "рецепт", "рецепта", "рецептов"))
                        .font(.caption)
                        .foregroundStyle(stamped ? Theme.herb : Color.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
            Text(country.cuisine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: Route.recipe(recipe.id)) {
                            HStack(spacing: 10) {
                                DishArtwork(recipe: recipe, showsYear: false)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(recipe.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .frame(width: 110, alignment: .leading)
                            }
                            .padding(8)
                            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            NavigationLink(value: Route.country(country.code)) {
                Text("Все блюда кухни")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Машина времени: рецепты на шкале истории — от Вавилона до наших дней.
struct TimeMachineView: View {
    @Environment(\.catalog) private var catalog

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Путешествие по истории кухни: каждое блюдо — на своём месте во времени. Для старинных рецептов есть оригинальный текст источника и современная адаптация.")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                ForEach(catalog.eras) { era in
                    let recipes = catalog.datedRecipes.filter { era.contains($0.year ?? .min) }
                    if !recipes.isEmpty {
                        EraHeader(era: era)
                        ForEach(recipes) { recipe in
                            TimelineRow(recipe: recipe)
                        }
                    }
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle("Машина времени")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EraHeader: View {
    let era: Era

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(era.range.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Theme.gold)
            Text(era.title)
                .font(.display(.title2))
            Text(era.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 22)
        .padding(.bottom, 14)
    }
}

private struct TimelineRow: View {
    let recipe: Recipe

    @Environment(\.catalog) private var catalog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(YearText.label(for: recipe) ?? "")
                .font(.system(.footnote, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.gold)
                .multilineTextAlignment(.trailing)
                .frame(width: 78, alignment: .trailing)
                .padding(.top, 14)
            VStack(spacing: 0) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
                    .padding(.top, 17)
                Rectangle()
                    .fill(Theme.gold.opacity(0.35))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)
            NavigationLink(value: Route.recipe(recipe.id)) {
                HStack(spacing: 12) {
                    DishArtwork(recipe: recipe, showsYear: false)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.title)
                            .font(.display(.subheadline))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(recipe.source?.title ?? recipe.origin ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
