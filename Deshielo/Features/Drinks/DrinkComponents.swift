import MapKit
import SwiftUI

/// Строка списка: иллюстрация, название и подпись.
struct DrinkRow<Artwork: View>: View {
    let title: String
    let subtitle: String
    var trailing: String?
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        HStack(spacing: 14) {
            artwork()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.display(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.title3)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Плитка для горизонтальных лент: стили вина и типы чая.
struct DrinkTile<Artwork: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title)
                .font(.display(.subheadline))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 150)
        .contentShape(Rectangle())
    }
}

/// Горизонтальная лента плиток с заголовком.
struct DrinkShelf<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    content()
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

/// Шапка страницы напитка: иллюстрация, надзаголовок, название, оригинальное название и описание.
struct DrinkHero<Artwork: View>: View {
    let eyebrow: String
    let title: String
    var original: String?
    let summary: String
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            artwork()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.display(.largeTitle, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let original, original != title {
                    Text(original)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.secondary)
                }
            }
            Text(summary)
                .font(.system(.body, design: .serif))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Шкала от 1 до 5: тело, кислотность, танины.
struct ScaleBar: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(value) из 5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { index in
                    Capsule()
                        .fill(index <= value ? Theme.accent : Theme.surfaceSecondary)
                        .frame(height: 7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) из 5")
    }
}

/// Облако ароматов.
struct AromaCloud: View {
    let aromas: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(aromas, id: \.self) { aroma in
                Text(aroma)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surfaceSecondary, in: Capsule())
            }
        }
    }
}

/// Кнопка поиска в Vivino. Открывает их сайт или приложение — своего API у Vivino нет.
struct VivinoButton: View {
    let title: String
    let query: String

    var body: some View {
        if let url = VivinoLink.search(query) {
            Link(destination: url) {
                HStack {
                    Label(title, systemImage: "magnifyingglass")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .foregroundStyle(Theme.accent)
        }
    }
}

/// Небольшая карта с меткой — где растёт виноград или чай.
struct PlaceMap: View {
    let title: String
    let latitude: Double
    let longitude: Double
    var symbol = "mappin"
    var span = 6.0

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))) {
            Marker(title, systemImage: symbol, coordinate: coordinate)
                .tint(Theme.accent)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityLabel("Карта: \(title)")
    }
}

/// Плашка-ссылка: «Карта вин и чая», «Дегустационный дневник».
struct DrinkLinkCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let route: Route

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.surfaceSecondary, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

/// Блок «Что налить» в рецепте: стиль вина и чай с объяснением, почему они подходят.
struct DrinkPairingSection: View {
    let recipe: Recipe

    @Environment(\.drinks) private var drinks
    @Environment(\.pairings) private var pairings

    private var wine: (pick: DrinkSuggestion, style: WineStyle)? {
        guard DrinksConfig.showsWine, let pick = pairings.wine(for: recipe), let style = drinks.style(pick.id)
        else { return nil }
        return (pick: pick, style: style)
    }

    private var tea: (pick: DrinkSuggestion, tea: Tea)? {
        guard let pick = pairings.tea(for: recipe), let tea = drinks.tea(pick.id) else { return nil }
        return (pick: pick, tea: tea)
    }

    var body: some View {
        let wine = self.wine
        let tea = self.tea
        if wine != nil || tea != nil {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Что налить")
                if let wine {
                    NavigationLink(value: Route.wineStyle(wine.style.id)) {
                        PairingCard(kind: "Вино", title: wine.style.name, note: wine.style.pairing.note,
                                    ingredients: pairings.ingredientNames(wine.pick)) {
                            DrinkArtwork(style: wine.style)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let tea {
                    NavigationLink(value: Route.tea(tea.tea.id)) {
                        PairingCard(kind: "Чай", title: tea.tea.name, note: tea.tea.pairing.note,
                                    ingredients: pairings.ingredientNames(tea.pick)) {
                            DrinkArtwork(tea: tea.tea)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PairingCard<Artwork: View>: View {
    let kind: String
    let title: String
    let note: String
    let ingredients: [String]
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            artwork()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.display(.headline))
                    .foregroundStyle(.primary)
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !ingredients.isEmpty {
                    Text("В блюде: \(ingredients.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Theme.herb)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card()
        .multilineTextAlignment(.leading)
    }
}

/// Рецепты, к которым подходит напиток.
struct DrinkRecipesShelf: View {
    let title: String
    let note: String?
    let recipes: [Recipe]

    var body: some View {
        if !recipes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: title)
                    if let note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                RecipeShelf(recipes: recipes)
            }
            .padding(.horizontal, -20)
        }
    }
}
