import SwiftUI

/// Карточка рецепта: история блюда, источник, ингредиенты с пересчётом порций, шаги с таймерами.
struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile
    @Environment(ShoppingStore.self) private var shopping
    @Environment(TimerCenter.self) private var timers
    @Environment(Router.self) private var router
    @Environment(CommunityStore.self) private var community

    @State private var servings: Int
    @State private var checked: Set<Int> = []
    @State private var activeTerm: GlossaryTerm?
    @State private var sheet: DetailSheet?
    @State private var toast: String?

    enum DetailSheet: String, Identifiable {
        case note, plan, cooked, order
        var id: String { rawValue }
    }

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    private var scale: Double { Double(servings) / Double(recipe.servings) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero
                actions
                story
                if let source = recipe.source {
                    SourceCard(source: source)
                }
                IngredientsSection(recipe: recipe, servings: $servings, checked: $checked,
                                   onAddToShopping: addToShopping)
                StepsSection(recipe: recipe,
                             onTerm: { activeTerm = $0 },
                             onTimer: startTimer)
                extras
                DrinkPairingSection(recipe: recipe)
                personal
                ReviewsSection(target: .catalog(recipe.id), recipeTitle: recipe.title,
                               summary: community.rating(forCatalog: recipe.id)) { toast = $0 }
                Text(disclaimer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    profile.toggleFavorite(recipe.id)
                } label: {
                    Image(systemName: profile.isFavorite(recipe.id) ? "heart.fill" : "heart")
                }
                .accessibilityLabel(profile.isFavorite(recipe.id) ? "Убрать из избранного" : "В избранное")
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { cookButton }
        .sheet(item: $activeTerm) { term in
            TermSheet(term: term)
        }
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
        }
        .sensoryFeedback(.selection, trigger: profile.isFavorite(recipe.id))
        .toast($toast)
        .onAppear { profile.markViewed(recipe.id) }
    }

    // MARK: - Шапка

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            DishArtwork(recipe: recipe)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.originLine(in: catalog).uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Text(recipe.title)
                    .font(.display(.largeTitle, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = recipe.subtitle {
                    Text(subtitle)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.secondary)
                }
                if let rating = community.rating(forCatalog: recipe.id) {
                    HStack(spacing: 6) {
                        RatingStars(value: rating.average)
                        Text(RatingText.summary(rating))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let chef = catalog.chef(recipe.chef) {
                    NavigationLink(value: Route.chef(chef.id)) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                            Text(chef.name)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            metaGrid
            TimeBreakdownBar(recipe: recipe)
            if !recipe.diets.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recipe.diets) { diet in
                        Tag(title: diet.title, systemImage: diet.symbol, tint: Theme.herb)
                    }
                }
            }
        }
    }

    private var metaGrid: some View {
        HStack(spacing: 0) {
            MetaCell(value: DurationText.short(minutes: recipe.activeMinutes), caption: "время")
            Divider().frame(height: 32)
            MetaCell(value: recipe.difficultyTitle, caption: "сложность")
            Divider().frame(height: 32)
            MetaCell(value: "\(recipe.servings)",
                     caption: RussianPlural.form(recipe.servings, "порция", "порции", "порций"))
            if let calories = recipe.calories {
                Divider().frame(height: 32)
                MetaCell(value: "≈\u{2009}\(calories)", caption: "ккал/порция")
            }
        }
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Действия

    private var actions: some View {
        let hasNote = !profile.note(for: recipe.id).isEmpty
        let cookedTimes = profile.timesCooked(recipe.id)
        return HStack(spacing: 4) {
            ActionCircle(title: "В меню", systemImage: "calendar.badge.plus") { sheet = .plan }
            ActionCircle(title: "Заметка", systemImage: hasNote ? "note.text" : "square.and.pencil",
                         isActive: hasNote) { sheet = .note }
            ActionCircle(title: "В дневник", systemImage: "checkmark.seal",
                         isActive: cookedTimes > 0) { sheet = .cooked }
            ActionCircle(title: "Заказать", systemImage: "takeoutbag.and.cup.and.straw") { sheet = .order }
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: DetailSheet) -> some View {
        switch sheet {
        case .note:
            NoteEditorSheet(recipe: recipe)
        case .plan:
            PlanDaySheet { day in
                profile.addToPlan(recipe.id, on: day)
                toast = "Добавлено в меню: \(MealPlanView.dayTitle(day).lowercased())"
            }
        case .cooked:
            CookedSheet(recipe: recipe) { result in
                toast = CookedRecorder.record(result, recipe: recipe, profile: profile, catalog: catalog)
                Task {
                    if let message = await CookedRecorder.publish(result, recipe: recipe, community: community) {
                        toast = message
                    }
                }
            }
        case .order:
            OrderReadySheet(recipe: recipe) {
                addToShopping()
            }
        }
    }

    // MARK: - Текстовые разделы

    private var story: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "О блюде")
            Text(recipe.story)
                .font(.system(.body, design: .serif))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var extras: some View {
        if let plating = recipe.plating {
            InfoBlock(title: "Подача", systemImage: "sparkles", text: plating)
        }
        if !recipe.tips.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Секреты")
                ForEach(recipe.tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(Theme.gold)
                        Text(tip)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if let pairing = recipe.pairing {
            InfoBlock(title: "С чем подавать", systemImage: "wineglass", text: pairing)
        }
    }

    @ViewBuilder
    private var personal: some View {
        let note = profile.note(for: recipe.id)
        let times = profile.timesCooked(recipe.id)
        if !note.isEmpty {
            InfoBlock(title: "Моя заметка", systemImage: "note.text", text: note)
        }
        if times > 0 {
            Label("Вы готовили это блюдо \(times) \(RussianPlural.form(times, "раз", "раза", "раз"))",
                  systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.herb)
        }
    }

    private var disclaimer: String {
        var text = "Калорийность указана приблизительно."
        if recipe.chef != nil {
            text = "Рецепт — домашняя адаптация по мотивам блюда шефа. " + text
        }
        if recipe.isHistoric {
            text = "Исторические рецепты адаптированы под современные продукты и технику. " + text
        }
        return text
    }

    private var cookButton: some View {
        Button {
            router.startCooking(recipe, servings: servings)
        } label: {
            Label("Начать готовить", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var shareText: String {
        var lines = [recipe.title]
        if let subtitle = recipe.subtitle { lines.append(subtitle) }
        lines.append("")
        lines.append(recipe.summary)
        lines.append("")
        lines.append("Ингредиенты (\(recipe.servingsText)):")
        for ingredient in recipe.ingredients {
            let amount = AmountFormatter.format(amount: ingredient.amount, unit: ingredient.unit)
            lines.append(amount.isEmpty ? "• \(ingredient.name)" : "• \(ingredient.name) — \(amount)")
        }
        lines.append("")
        lines.append("Рецепт из приложения Deshielo")
        return lines.joined(separator: "\n")
    }

    // MARK: - Действия

    private func addToShopping() {
        let count = shopping.add(recipe: recipe, scale: scale, catalog: catalog,
                                 includeStaples: profile.includeStaples)
        toast = "В покупках: +\(RussianPlural.phrase(count, "продукт", "продукта", "продуктов"))"
    }

    private func startTimer(_ step: RecipeStep, index: Int) {
        guard let minutes = step.timer else { return }
        let label = step.title ?? "Шаг \(index + 1)"
        timers.start(label: label, minutes: minutes, recipe: recipe)
        toast = "Таймер «\(label)» на \(DurationText.timerTitle(minutes: minutes))"
    }
}

struct MetaCell: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Текстовый блок с заголовком и иконкой.
struct InfoBlock: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
