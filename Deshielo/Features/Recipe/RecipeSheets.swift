import SwiftUI

/// Термин из «Словаря шефа».
struct TermSheet: View {
    let term: GlossaryTerm

    @Environment(\.catalog) private var catalog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(term.term)
                        .font(.display(.title, weight: .bold))
                    Text(term.definition)
                        .font(.system(.body, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    if let tip = term.tip {
                        Label(tip, systemImage: "lightbulb")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let recipes = catalog.recipes(usingTechnique: term.id)
                    if !recipes.isEmpty {
                        Text("Встречается в рецептах")
                            .font(.headline)
                            .padding(.top, 8)
                        ForEach(recipes) { recipe in
                            Text("• \(recipe.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Личная заметка к рецепту.
struct NoteEditorSheet: View {
    let recipe: Recipe

    @Environment(ProfileStore.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Например: в следующий раз меньше соли, а мясо держать на 10 минут дольше")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle("Заметка")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            profile.setNote(text, for: recipe.id)
                            dismiss()
                        }
                    }
                }
                .onAppear { text = profile.note(for: recipe.id) }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Выбор дня для меню на неделю.
struct PlanDaySheet: View {
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
                        Button {
                            onPick(day)
                            dismiss()
                        } label: {
                            HStack {
                                Text(MealPlanView.dayTitle(day))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                } footer: {
                    Text("Все продукты из меню можно одной кнопкой отправить в список покупок.")
                }
            }
            .navigationTitle("Добавить в меню")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Запись в дневник готовки: оценка и заметка.
struct CookedSheet: View {
    let recipe: Recipe
    let onSave: (Int?, String?) -> Void

    @Environment(\.catalog) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Как получилось?") {
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                rating = value
                            } label: {
                                Image(systemName: value <= rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(Theme.gold)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(value) из 5")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                Section("Заметка в дневник") {
                    TextField("Что изменить в следующий раз", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let country = catalog.country(recipe.country) {
                    Section {
                        Label("Блюдо засчитается в кулинарный паспорт: \(country.flag) \(country.name)",
                              systemImage: "seal")
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Записать") {
                        onSave(rating == 0 ? nil : rating, note)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// «Не хочется готовить»: готовое блюдо из доставки или ресторан поблизости.
struct OrderReadySheet: View {
    let recipe: Recipe
    let onCollectGroceries: () -> Void

    @Environment(\.catalog) private var catalog
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(catalog.delivery.filter { $0.kind != .groceries }) { service in
                        Button {
                            openURL(service.url(for: recipe.title))
                        } label: {
                            ServiceRow(service: service,
                                       subtitle: service.kind == .restaurants ? "Заказать готовое" : "Найти, где попробовать")
                        }
                    }
                } header: {
                    Text("Не хочется готовить?")
                } footer: {
                    Text("Откроется приложение или сайт сервиса с поиском «\(recipe.title)». Deshielo не связан с этими сервисами.")
                }
                Section {
                    Button {
                        onCollectGroceries()
                        dismiss()
                    } label: {
                        Label("Собрать продукты в список покупок", systemImage: "cart.badge.plus")
                    }
                } footer: {
                    Text("Из списка покупок продукты можно заказать в Лавке, Самокате, ВкусВилле и других сервисах.")
                }
            }
            .navigationTitle("Заказать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Строка сервиса доставки: цветной значок с первой буквой и название.
struct ServiceRow: View {
    let service: DeliveryService
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(String(service.name.prefix(1)))
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(Color(hex: service.color), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(UIColor(hex: service.color).luminance > 0.6 ? Color.black : Color.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .foregroundStyle(.primary)
                if let text = subtitle ?? service.note {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}
