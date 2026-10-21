import SwiftUI
import WidgetKit

struct RecipeEntry: TimelineEntry {
    let date: Date
    let recipe: Recipe?
    let fact: FoodFact?
}

struct RecipeOfTheDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecipeEntry {
        RecipeEntry(date: .now, recipe: Catalog.bundled.recipes.first, fact: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecipeEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecipeEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
        // Запись на сегодня и на завтра: в полночь виджет сам переключится на новый рецепт.
        let timeline = Timeline(entries: [entry(for: now), entry(for: tomorrow)], policy: .after(dayAfter))
        completion(timeline)
    }

    private func entry(for date: Date) -> RecipeEntry {
        let catalog = Catalog.bundled
        return RecipeEntry(date: date,
                           recipe: DailyPick.recipe(for: date, in: catalog),
                           fact: DailyPick.fact(for: date, in: catalog))
    }
}

struct RecipeOfTheDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.recipeOfTheDay, provider: RecipeOfTheDayProvider()) { entry in
            RecipeOfTheDayView(entry: entry)
        }
        .configurationDisplayName("Рецепт дня")
        .description("Каждый день новое блюдо — от вавилонских табличек до звёздных ресторанов.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct RecipeOfTheDayView: View {
    let entry: RecipeEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let recipe = entry.recipe {
            content(recipe)
                .widgetURL(DeepLink.recipe(recipe.id).url)
        } else {
            Text("Deshielo")
                .font(.display(.headline))
                .containerBackground(for: .widget) { Theme.surface }
        }
    }

    @ViewBuilder
    private func content(_ recipe: Recipe) -> some View {
        switch family {
        case .systemSmall:
            small(recipe)
        case .systemMedium:
            medium(recipe)
        case .systemLarge:
            large(recipe)
        case .accessoryRectangular:
            rectangular(recipe)
        case .accessoryInline:
            Text("Рецепт дня: \(recipe.title)")
                .containerBackground(for: .widget) { Color.clear }
        default:
            small(recipe)
        }
    }

    private func small(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("РЕЦЕПТ ДНЯ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            Text(recipe.title)
                .font(.display(.headline))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text(DurationText.short(minutes: recipe.activeMinutes))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(for: .widget) {
            ZStack {
                DishArtwork(recipe: recipe, showsYear: false)
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func medium(_ recipe: Recipe) -> some View {
        HStack(spacing: 14) {
            DishArtwork(recipe: recipe)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text("РЕЦЕПТ ДНЯ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(recipe.title)
                    .font(.display(.headline))
                    .lineLimit(2)
                Text(recipe.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Text(metaLine(recipe))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .containerBackground(for: .widget) { Theme.surface }
    }

    private func large(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DishArtwork(recipe: recipe)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("РЕЦЕПТ ДНЯ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.accent)
            Text(recipe.title)
                .font(.display(.title3))
                .lineLimit(2)
            Text(recipe.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(metaLine(recipe))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let fact = entry.fact {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("ФАКТ ДНЯ")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.gold)
                    Text(fact.text)
                        .font(.system(.caption, design: .serif))
                        .lineLimit(3)
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) { Theme.surface }
    }

    private func rectangular(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Рецепт дня")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text(recipe.title)
                .font(.headline)
                .lineLimit(2)
            Text(DurationText.short(minutes: recipe.activeMinutes))
                .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private func metaLine(_ recipe: Recipe) -> String {
        var parts = [DurationText.short(minutes: recipe.activeMinutes), recipe.difficultyTitle]
        if let country = Catalog.bundled.country(recipe.country) {
            parts.append(country.flag)
        }
        return parts.joined(separator: " · ")
    }
}
