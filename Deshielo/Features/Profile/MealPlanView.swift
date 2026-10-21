import SwiftUI

/// Меню на неделю: блюда по дням и один список покупок на всю неделю.
struct MealPlanView: View {
    private struct PlanDay: Identifiable {
        let date: Date
        var id: String { DayKey.make(date) }
    }

    @Environment(\.catalog) private var catalog
    @Environment(ProfileStore.self) private var profile
    @Environment(ShoppingStore.self) private var shopping

    @State private var pickerDay: PlanDay?
    @State private var toast: String?

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        List {
            Section {
                Button {
                    addWeekToShopping()
                } label: {
                    Label("Все продукты меню — в покупки", systemImage: "cart.badge.plus")
                }
                .disabled(profile.plannedCount == 0)
            } footer: {
                Text("Одинаковые продукты из разных блюд сложатся автоматически.")
            }

            ForEach(days, id: \.self) { day in
                Section(Self.dayTitle(day)) {
                    let ids = profile.plan(on: day)
                    ForEach(ids, id: \.self) { id in
                        if let recipe = catalog.recipe(id) {
                            NavigationLink(value: Route.recipe(id)) {
                                RecipeRow(recipe: recipe)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            profile.removeFromPlan(ids[offset], on: day)
                        }
                    }
                    Button {
                        pickerDay = PlanDay(date: day)
                    } label: {
                        Label("Добавить блюдо", systemImage: "plus")
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Меню на неделю")
        .sheet(item: $pickerDay) { day in
            RecipePickerSheet { recipe in
                profile.addToPlan(recipe.id, on: day.date)
            }
        }
        .toast($toast)
    }

    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInTomorrow(date) { return "Завтра" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM"
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func addWeekToShopping() {
        var total = 0
        for day in days {
            for id in profile.plan(on: day) {
                guard let recipe = catalog.recipe(id) else { continue }
                total += shopping.add(recipe: recipe, scale: 1, catalog: catalog, includeStaples: profile.includeStaples)
            }
        }
        toast = "В покупках: +\(RussianPlural.phrase(total, "продукт", "продукта", "продуктов"))"
    }
}

/// Выбор рецепта с поиском.
struct RecipePickerSheet: View {
    let onPick: (Recipe) -> Void

    @Environment(\.catalog) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(catalog.search(query)) { recipe in
                Button {
                    onPick(recipe)
                    dismiss()
                } label: {
                    RecipeRow(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Найти рецепт")
            .navigationTitle("Выберите блюдо")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
