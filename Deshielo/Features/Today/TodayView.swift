import SwiftUI

/// Главный экран: рецепт и факт дня, сезонное, машина времени, коллекции.
struct TodayView: View {
    @Environment(\.catalog) private var catalog
    @Environment(Router.self) private var router
    @Environment(TimerCenter.self) private var timers
    @Environment(ProfileStore.self) private var profile

    private var today: Date { .now }
    private var month: Int { Calendar.current.component(.month, from: today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                if let recipe = DailyPick.recipe(for: today, in: catalog) {
                    NavigationLink(value: Route.recipe(recipe.id)) {
                        RecipeCard(recipe: recipe, eyebrow: "Рецепт дня", height: 300)
                    }
                    .buttonStyle(.plain)
                }

                if !timers.timers.isEmpty {
                    ActiveTimersCard()
                }

                if let fact = DailyPick.fact(for: today, in: catalog) {
                    FactCard(fact: fact)
                }

                recentSection

                SeasonSection(month: month)

                TimeMachineTeaser()

                collectionsSection

                surpriseButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle("Сегодня")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dateText(today))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Что приготовим?")
                .font(.display(.largeTitle, weight: .bold))
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = profile.profile.recent.prefix(8).compactMap { catalog.recipe($0) }
        if recent.count >= 2 {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Вы недавно смотрели")
                RecipeShelf(recipes: Array(recent), tileWidth: 130)
                    .padding(.horizontal, -20)
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Коллекции", subtitle: "От Вавилона до звёздных ресторанов")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(catalog.collections) { collection in
                    NavigationLink(value: Route.collection(collection.id)) {
                        CollectionTile(collection: collection, count: catalog.recipes(inCollection: collection.id).count)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var surpriseButton: some View {
        Button {
            if let recipe = catalog.recipes.randomElement() {
                router.push(.recipe(recipe.id))
            }
        } label: {
            Label("Удиви меня", systemImage: "sparkles")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM"
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Плитка коллекции.
struct CollectionTile: View {
    let collection: RecipeCollection
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: collection.symbol)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.95))
            Spacer(minLength: 8)
            Text(collection.title)
                .font(.display(.headline))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(RussianPlural.phrase(count, "рецепт", "рецепта", "рецептов"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(
            LinearGradient(colors: collection.palette.prefix(2).map(Color.init(hex:)),
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        )
    }
}

/// «Знаете ли вы?» — кулинарный факт дня.
struct FactCard: View {
    let fact: FoodFact

    @Environment(\.catalog) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Факт дня", systemImage: "lightbulb")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.gold)
            Text(fact.text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let recipe = catalog.recipe(fact.recipe) {
                NavigationLink(value: Route.recipe(recipe.id)) {
                    HStack(spacing: 6) {
                        Text("Рецепт: \(recipe.title)")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.parchment.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Сезонные продукты месяца и рецепты с ними.
struct SeasonSection: View {
    let month: Int

    @Environment(\.catalog) private var catalog

    var body: some View {
        if let season = catalog.season(for: month) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Сейчас в сезоне", subtitle: season.note)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(season.keys, id: \.self) { key in
                            if let item = catalog.pantryItem(key) {
                                Text("\(item.emoji) \(item.name)")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Theme.surfaceSecondary, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
                RecipeShelf(recipes: catalog.seasonalRecipes(month: month))
                    .padding(.horizontal, -20)
            }
        }
    }
}

/// Анонс «Машины времени»: шкала эпох.
struct TimeMachineTeaser: View {
    @Environment(\.catalog) private var catalog

    var body: some View {
        NavigationLink(value: Route.timeMachine) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Машина времени")
                            .font(.display(.title3))
                        Text("Рецепты от вавилонских табличек до наших дней")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "hourglass")
                        .font(.title2)
                        .foregroundStyle(Theme.gold)
                }
                timeline
            }
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var timeline: some View {
        let years = catalog.datedRecipes.compactMap(\.year)
        let marks = [years.first, -160, 950, 1390, 1691, 1871, 1961, years.last].compactMap { $0 }
        return HStack(spacing: 0) {
            ForEach(Array(marks.enumerated()), id: \.offset) { item in
                VStack(spacing: 6) {
                    Circle()
                        .fill(item.offset == marks.count - 1 ? Theme.accent : Theme.gold)
                        .frame(width: 8, height: 8)
                    Text(YearText.short(item.element).replacingOccurrences(of: " до н. э.", with: "\u{00A0}до н.э."))
                        .font(.system(size: 9, weight: .medium, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) {
            Rectangle()
                .fill(Theme.gold.opacity(0.4))
                .frame(height: 1)
                .padding(.top, 4)
        }
    }
}

/// Активные таймеры на главном экране.
struct ActiveTimersCard: View {
    @Environment(TimerCenter.self) private var timers
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Таймеры", systemImage: "timer")
                .font(.headline)
            ForEach(timers.timers) { timer in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.label)
                            .font(.subheadline.weight(.semibold))
                        Text(timer.recipeTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(timerInterval: timer.startDate...timer.endDate, countsDown: true)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 70, alignment: .trailing)
                    Button {
                        timers.cancel(timer)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Остановить таймер")
                }
            }
        }
        .card()
    }
}
