import SwiftUI

/// Историческая справка: оригинальный текст, перевод или пересказ, примечание об адаптации.
struct SourceCard: View {
    let source: RecipeSource

    @State private var showsOriginal = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Источник", systemImage: "scroll")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.gold)
            Text(source.title)
                .font(.display(.headline))
                .fixedSize(horizontal: false, vertical: true)
            let byline = [source.author, source.date].compactMap { $0 }.joined(separator: " · ")
            if !byline.isEmpty {
                Text(byline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let quote = source.quote {
                if source.translation != nil {
                    Picker("Текст", selection: $showsOriginal) {
                        Text("Оригинал").tag(true)
                        Text("Перевод").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                Text(showsOriginal ? quote : (source.translation ?? quote))
                    .font(.system(.body, design: .serif))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.gold)
                            .frame(width: 2)
                    }
                if showsOriginal, let language = source.quoteLanguage {
                    Text("Язык оригинала: \(language)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let retelling = source.retelling {
                Text("Пересказ источника")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(retelling)
                    .font(.system(.body, design: .serif))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.gold)
                            .frame(width: 2)
                    }
            }
            if let note = source.note {
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.parchment.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Ингредиенты: пересчёт на любое число порций и отметки «уже на столе».
struct IngredientsSection: View {
    let recipe: Recipe
    @Binding var servings: Int
    @Binding var checked: Set<Int>
    let onAddToShopping: () -> Void

    @Environment(\.catalog) private var catalog

    private var scale: Double { Double(servings) / Double(recipe.servings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Ингредиенты",
                          subtitle: checked.isEmpty ? "Нажмите на продукт, чтобы отметить его" : "Готово \(checked.count) из \(recipe.ingredients.count)")
            HStack {
                Text(RussianPlural.phrase(servings, "порция", "порции", "порций"))
                    .font(.headline)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: servings)
                if servings != recipe.servings {
                    Text("в рецепте — \(recipe.servings)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper("Порции", value: $servings, in: 1...24)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recipe.ingredientGroups.enumerated()), id: \.offset) { group in
                    if let title = group.element.title {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, group.offset == 0 ? 0 : 14)
                            .padding(.bottom, 4)
                    }
                    ForEach(group.element.items, id: \.index) { item in
                        IngredientLine(ingredient: item.ingredient,
                                       scale: scale,
                                       emoji: catalog.pantryItem(item.ingredient.key)?.emoji,
                                       isChecked: checked.contains(item.index)) {
                            if checked.contains(item.index) {
                                checked.remove(item.index)
                            } else {
                                checked.insert(item.index)
                            }
                        }
                        Divider()
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: checked)

            Button(action: onAddToShopping) {
                Label("В список покупок", systemImage: "cart.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

struct IngredientLine: View {
    let ingredient: Ingredient
    let scale: Double
    let emoji: String?
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Theme.herb : Color.secondary.opacity(0.5))
                Text(emoji ?? "•")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ingredient.optional ? "\(ingredient.name) · по желанию" : ingredient.name)
                        .font(.body)
                        .strikethrough(isChecked)
                        .multilineTextAlignment(.leading)
                    if let note = ingredient.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Text(AmountFormatter.format(amount: ingredient.amount.map { $0 * scale }, unit: ingredient.unit))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .opacity(isChecked ? 0.55 : 1)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Шаги приготовления с таймерами, температурой и техниками.
struct StepsSection: View {
    let recipe: Recipe
    let onTerm: (GlossaryTerm) -> Void
    let onTimer: (RecipeStep, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Приготовление",
                          subtitle: RussianPlural.phrase(recipe.steps.count, "шаг", "шага", "шагов"))
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { item in
                StepCard(number: item.offset + 1, step: item.element, recipe: recipe, onTerm: onTerm) {
                    onTimer(item.element, item.offset)
                }
            }
        }
    }
}

struct StepCard: View {
    let number: Int
    let step: RecipeStep
    let recipe: Recipe
    let onTerm: (GlossaryTerm) -> Void
    let onTimer: () -> Void

    @Environment(\.catalog) private var catalog
    @Environment(TimerCenter.self) private var timers

    private var timerLabel: String { step.title ?? "Шаг \(number)" }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                if let title = step.title {
                    HStack(spacing: 8) {
                        Image(systemName: StepIcon.symbol(for: step))
                            .foregroundStyle(Theme.accent)
                        Text(title)
                            .font(.headline)
                    }
                }
                Text(step.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                chips
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        let terms = step.techniques.compactMap { catalog.term($0) }
        if step.timer != nil || step.temperature != nil || !terms.isEmpty {
            FlowLayout(spacing: 6) {
                if let minutes = step.timer {
                    timerChip(minutes: minutes)
                }
                if let temperature = step.temperature {
                    Tag(title: "\(temperature) °C", systemImage: "thermometer", tint: .orange)
                }
                ForEach(terms) { term in
                    Button {
                        onTerm(term)
                    } label: {
                        Tag(title: term.term, systemImage: "book.closed", tint: Theme.gold)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func timerChip(minutes: Double) -> some View {
        if let running = timers.timer(label: timerLabel, recipeID: recipe.id) {
            Button {
                timers.cancel(running)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                    Text(timerInterval: running.startDate...running.endDate, countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Остановить таймер")
        } else {
            Button(action: onTimer) {
                Tag(title: "Таймер · \(DurationText.timerTitle(minutes: minutes))", systemImage: "timer", tint: Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Иконка шага по ключевым словам: огонь, духовка, холодильник, нож…
enum StepIcon {
    private static let rules: [(symbol: String, keys: [String])] = [
        ("fork.knife", ["подайте", "подав", "сервир"]),
        ("snowflake", ["холодильник", "морозилк", "охлад", "заморо", "остуд", "застуд"]),
        ("oven", ["духовк", "запек", "выпек"]),
        ("flame", ["обжар", "жарьте", "сковород", "карамел", "вытоп", "раскал"]),
        ("drop", ["свар", "варите", "кипят", "бульон", "бланшир", "отвар"]),
        ("scissors", ["нарез", "наруб", "нашинк", "натр", "измельч"]),
        ("hand.raised", ["замес", "тесто", "лепит", "слепит", "сформ"]),
        ("tornado", ["взбе", "венчик", "миксер", "пробейте"]),
        ("hourglass", ["оставьте", "настаива", "маринуй", "отдохн", "расстой", "посол"])
    ]

    static func symbol(for step: RecipeStep) -> String {
        if let title = step.title?.lowercased(), let symbol = match(title) {
            return symbol
        }
        return match(step.text.lowercased()) ?? "circle.dotted"
    }

    private static func match(_ text: String) -> String? {
        for rule in rules where rule.keys.contains(where: { text.contains($0) }) {
            return rule.symbol
        }
        return nil
    }
}
