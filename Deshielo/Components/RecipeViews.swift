import SwiftUI

/// Большая карточка рецепта: обложка, заголовок, описание.
struct RecipeCard: View {
    let recipe: Recipe
    var eyebrow: String?
    var height: CGFloat = 250

    @Environment(\.catalog) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DishArtwork(recipe: recipe)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accent)
                }
                Text(recipe.title)
                    .font(.display(.title2))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(recipe.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(alignment: .firstTextBaseline) {
                    Text(recipe.originLine(in: catalog))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    RecipeMetaLine(recipe: recipe, compact: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
    }
}

/// Строка рецепта для списков.
struct RecipeRow: View {
    let recipe: Recipe
    var detail: String?

    @Environment(\.catalog) private var catalog

    var body: some View {
        HStack(spacing: 14) {
            DishArtwork(recipe: recipe, showsYear: false)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.display(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(detail ?? recipe.originLine(in: catalog))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                RecipeMetaLine(recipe: recipe, compact: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Плитка рецепта для сеток и горизонтальных лент.
struct RecipeTile: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DishArtwork(recipe: recipe)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(recipe.title)
                .font(.display(.subheadline))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            RecipeMetaLine(recipe: recipe, compact: true)
        }
        .contentShape(Rectangle())
    }
}

/// Время, сложность и порции одной строкой.
struct RecipeMetaLine: View {
    let recipe: Recipe
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Label(DurationText.short(minutes: recipe.activeMinutes), systemImage: "clock")
            DifficultyDots(level: recipe.difficulty)
            if !compact {
                Label(recipe.servingsText, systemImage: "person.2")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct DifficultyDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { index in
                Circle()
                    .fill(index <= level ? Theme.accent : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level <= 1 ? "Просто" : level == 2 ? "Средняя сложность" : "Сложно")
    }
}

/// Горизонтальная лента рецептов.
struct RecipeShelf: View {
    let recipes: [Recipe]
    var tileWidth: CGFloat = 150

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(recipes) { recipe in
                    NavigationLink(value: Route.recipe(recipe.id)) {
                        RecipeTile(recipe: recipe)
                            .frame(width: tileWidth)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// Шкала времени рецепта: подготовка, готовка, ожидание.
struct TimeBreakdownBar: View {
    private struct Segment: Identifiable {
        let id: String
        let minutes: Int
        let color: Color
    }

    let recipe: Recipe

    private var segments: [Segment] {
        [
            Segment(id: "Подготовка", minutes: recipe.prepMinutes, color: Theme.accent.opacity(0.45)),
            Segment(id: "Готовка", minutes: recipe.cookMinutes, color: Theme.accent),
            Segment(id: "Ожидание", minutes: recipe.restMinutes, color: Theme.gold.opacity(0.55))
        ].filter { $0.minutes > 0 }
    }

    var body: some View {
        let parts = segments
        let total = max(1, parts.reduce(0) { $0 + $1.minutes })
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let available = proxy.size.width - CGFloat(max(0, parts.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(part.color)
                            .frame(width: max(6, available * CGFloat(part.minutes) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                ForEach(parts) { part in
                    HStack(spacing: 5) {
                        Circle().fill(part.color).frame(width: 7, height: 7)
                        Text("\(part.id) · \(DurationText.short(minutes: part.minutes))")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
