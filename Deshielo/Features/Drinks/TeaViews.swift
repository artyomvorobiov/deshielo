import SwiftUI

/// Тип чая: как его делают, как заваривать и какие чаи к нему относятся.
struct TeaTypeView: View {
    let type: TeaType

    @Environment(\.drinks) private var drinks

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DrinkHero(eyebrow: "Тип чая", title: type.name, summary: type.summary) {
                    DrinkArtwork(teaType: type)
                }
                Label("Окисление: \(type.oxidation.lowercasedFirst)", systemImage: "leaf")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.herb)
                Text(type.description)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                BrewingCard(brewing: type.brewing, timers: nil)
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Чаи")
                    ForEach(drinks.teas(ofType: type.id)) { tea in
                        NavigationLink(value: Route.tea(tea.id)) {
                            DrinkRow(title: tea.name, subtitle: tea.origin, trailing: CountryName.flag(tea.country)) {
                                DrinkArtwork(tea: tea)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(type.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Чай: происхождение, ароматы, заваривание с таймерами проливов и блюда к нему.
struct TeaView: View {
    let tea: Tea

    @Environment(\.drinks) private var drinks
    @Environment(\.catalog) private var catalog
    @Environment(\.pairings) private var pairings
    @Environment(TastingStore.self) private var tastings

    @State private var newTasting: Tasting?

    var body: some View {
        let type = drinks.teaType(tea.type)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DrinkHero(eyebrow: "\(type?.name ?? "Чай") · \(CountryName.flag(tea.country)) \(CountryName.name(tea.country, catalog: catalog))",
                          title: tea.name, original: tea.original, summary: tea.summary) {
                    DrinkArtwork(tea: tea)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Ароматы")
                    AromaCloud(aromas: tea.aromas)
                }
                BrewingCard(brewing: tea.brewing, timers: tea)
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "История")
                    Text(tea.story)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Откуда", subtitle: tea.origin)
                    PlaceMap(title: tea.name, latitude: tea.lat, longitude: tea.lon, symbol: "leaf")
                }
                DrinkRecipesShelf(title: "К чему подать", note: tea.pairing.note, recipes: pairings.recipes(forTea: tea))
                if let recipe = catalog.recipe(tea.recipe) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Рецепт с этим чаем")
                        NavigationLink(value: Route.recipe(recipe.id)) {
                            RecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let type {
                    NavigationLink(value: Route.teaType(type.id)) {
                        DrinkRow(title: type.name, subtitle: type.summary) {
                            DrinkArtwork(teaType: type)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    newTasting = Tasting(kind: .tea, name: tea.name, teaID: tea.id)
                } label: {
                    Label("Записать дегустацию", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                TastingList(title: "Мои дегустации", tastings: tastings.tastings(tea: tea.id))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(tea.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $newTasting) { tasting in
            TastingEditorView(tasting: tasting, isNew: true)
        }
    }
}

/// Как заваривать: температура, сколько чая и воды, проливы. Для конкретного чая проливы запускают таймеры.
struct BrewingCard: View {
    let brewing: TeaBrewing
    /// Чай, для которого запускаются таймеры. Без него — только параметры.
    let timers: Tea?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Заваривание", systemImage: "cup.and.saucer")
                .font(.headline)
                .foregroundStyle(Theme.accent)
            HStack(spacing: 0) {
                MetaCell(value: "\(brewing.temperature) °C", caption: "вода")
                Divider().frame(height: 32)
                MetaCell(value: "\(AmountFormatter.number(brewing.grams, fractions: false)) г", caption: "чая")
                Divider().frame(height: 32)
                MetaCell(value: "\(brewing.water) мл", caption: "воды")
            }
            if !brewing.steeps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(brewing.steeps.count == 1
                         ? "Настаивать \(TeaBrewing.steepText(brewing.steeps[0]))"
                         : "Проливы: \(RussianPlural.phrase(brewing.steeps.count, "пролив", "пролива", "проливов"))")
                        .font(.subheadline.weight(.semibold))
                    if let tea = timers {
                        FlowLayout(spacing: 8) {
                            ForEach(Array(brewing.steeps.enumerated()), id: \.offset) { item in
                                SteepButton(tea: tea, index: item.offset, seconds: item.element,
                                            single: brewing.steeps.count == 1)
                            }
                        }
                        Text("Нажмите на пролив — запустится таймер, и придёт уведомление, когда пора сливать настой.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(brewing.steeps.map(TeaBrewing.steepText).joined(separator: " → "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let note = brewing.note {
                Text(note)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Кнопка пролива: запускает таймер или показывает обратный отсчёт.
private struct SteepButton: View {
    let tea: Tea
    let index: Int
    let seconds: Int
    let single: Bool

    @Environment(TimerCenter.self) private var timers

    private var label: String { single ? "Заваривание" : "Пролив \(index + 1)" }

    var body: some View {
        let running = timers.timer(label: label, recipeID: tea.timerOwnerID)
        Button {
            if let running {
                timers.cancel(running)
            } else {
                timers.start(label: label, minutes: Double(seconds) / 60, ownerID: tea.timerOwnerID,
                             title: tea.name, palette: tea.palette,
                             message: single
                                 ? "\(tea.name) заварился — пора разливать."
                                 : "\(tea.name): \(index + 1)-й пролив готов — сливайте настой.")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: running == nil ? "play.fill" : "stop.fill")
                    .font(.caption)
                if let running {
                    Text(timerInterval: running.startDate...running.endDate, countsDown: true)
                        .monospacedDigit()
                } else {
                    Text(single ? TeaBrewing.steepText(seconds) : "\(index + 1) · \(TeaBrewing.steepText(seconds))")
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(running == nil ? Theme.surfaceSecondary : Theme.accent, in: Capsule())
            .foregroundStyle(running == nil ? Color.primary : Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(running == nil
                            ? "\(label): \(TeaBrewing.steepText(seconds)), запустить таймер"
                            : "\(label): остановить таймер")
    }
}
