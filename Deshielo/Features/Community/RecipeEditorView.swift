import SwiftUI
import UIKit

/// Редактор рецепта сообщества: фото, описание, ингредиенты, шаги.
struct RecipeEditorView: View {
    let existing: CommunityRecipe?
    let onSaved: (CommunityRecipe) -> Void

    @Environment(\.catalog) private var catalog
    @Environment(CommunityStore.self) private var community
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecipeDraft
    @State private var ingredients: [EditableIngredient]
    @State private var steps: [EditableStep]
    @State private var newImages: [PickedImage] = []
    @State private var isSaving = false
    @State private var error: String?

    init(existing: CommunityRecipe?, onSaved: @escaping (CommunityRecipe) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        let draft = existing.map(RecipeDraft.init(recipe:)) ?? RecipeDraft()
        _draft = State(initialValue: draft)
        _ingredients = State(initialValue: draft.ingredients.isEmpty
                             ? [EditableIngredient(), EditableIngredient(), EditableIngredient()]
                             : draft.ingredients.map(EditableIngredient.init))
        _steps = State(initialValue: draft.steps.isEmpty
                       ? [EditableStep(), EditableStep()]
                       : draft.steps.map(EditableStep.init))
    }

    private var photoCount: Int { draft.keptPhotos.count + newImages.count }

    var body: some View {
        NavigationStack {
            CommunityGate(reason: "Войдите, чтобы опубликовать рецепт.") {
                form
            }
            .navigationTitle(existing == nil ? "Новый рецепт" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                if community.user != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button(draft.isPublished ? "Опубликовать" : "Сохранить", action: save)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var form: some View {
        Form {
            Section {
                photosRow
            } header: {
                Text("Фото")
            } footer: {
                Text("До \(RecipeDraft.maxPhotos) фото. Первое станет обложкой.")
            }

            Section("О блюде") {
                TextField("Название", text: $draft.title)
                    .font(.headline)
                TextField("Коротко: чем хорош рецепт", text: $draft.summary, axis: .vertical)
                    .lineLimit(2...4)
                TextField("История блюда (необязательно)", text: $draft.story, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section("Параметры") {
                Picker("Категория", selection: $draft.category) {
                    ForEach(RecipeCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                Picker("Кухня", selection: $draft.country) {
                    Text("Не указана").tag(String?.none)
                    ForEach(catalog.countries.sorted { $0.name < $1.name }) { country in
                        Text("\(country.flag) \(country.name)").tag(Optional(country.code))
                    }
                }
                Picker("Сложность", selection: $draft.difficulty) {
                    Text("Просто").tag(1)
                    Text("Средне").tag(2)
                    Text("Сложно").tag(3)
                }
                .pickerStyle(.segmented)
                Stepper("Порций: \(draft.servings)", value: $draft.servings, in: 1...50)
                Stepper("Подготовка: \(minutesText(draft.prepMinutes))", value: $draft.prepMinutes, in: 0...1440, step: 5)
                Stepper("Готовка: \(minutesText(draft.cookMinutes))", value: $draft.cookMinutes, in: 0...2880, step: 5)
            }

            Section {
                ForEach($ingredients) { $item in
                    IngredientEditorRow(item: $item)
                }
                .onDelete { ingredients.remove(atOffsets: $0) }
                .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    ingredients.append(EditableIngredient())
                } label: {
                    Label("Добавить ингредиент", systemImage: "plus")
                }
            } header: {
                Text("Ингредиенты")
            } footer: {
                Text("Количество можно не указывать — например, для соли по вкусу.")
            }

            Section {
                ForEach($steps) { $step in
                    StepEditorRow(step: $step, number: (steps.firstIndex { $0.id == step.id } ?? 0) + 1)
                }
                .onDelete { steps.remove(atOffsets: $0) }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    steps.append(EditableStep())
                } label: {
                    Label("Добавить шаг", systemImage: "plus")
                }
            } header: {
                Text("Приготовление")
            }

            Section {
                Toggle("Опубликовать для всех", isOn: $draft.isPublished)
            } footer: {
                Text(draft.isPublished
                     ? "Рецепт появится в ленте сообщества. Публикуя, вы подтверждаете, что текст и фото ваши."
                     : "Черновик видите только вы.")
            }

            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var photosRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(draft.keptPhotos) { photo in
                    EditablePhoto {
                        CommunityImage(url: photo.thumbnailURL)
                    } onRemove: {
                        draft.keptPhotos.removeAll { $0.name == photo.name }
                        draft.removedPhotoNames.append(photo.name)
                    }
                }
                ForEach(newImages) { picked in
                    EditablePhoto {
                        Image(uiImage: picked.image)
                            .resizable()
                            .scaledToFill()
                    } onRemove: {
                        newImages.removeAll { $0.id == picked.id }
                    }
                }
                if photoCount < RecipeDraft.maxPhotos {
                    PhotoSourceButton(maxCount: RecipeDraft.maxPhotos - photoCount) { images in
                        let free = RecipeDraft.maxPhotos - photoCount
                        newImages += images.prefix(max(0, free)).map(PickedImage.init)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "camera")
                                .font(.title3)
                            Text("Добавить")
                                .font(.caption)
                        }
                        .frame(width: 96, height: 96)
                        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Добавить фото")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func minutesText(_ minutes: Int) -> String {
        minutes == 0 ? "нет" : DurationText.short(minutes: minutes)
    }

    private func save() {
        var draft = draft
        draft.ingredients = ingredients.map(\.ingredient)
        draft.steps = steps.map(\.step)
        if let problem = draft.problem {
            error = problem
            return
        }
        error = nil
        isSaving = true
        draft.newPhotos = newImages.compactMap { ImageCompressor.jpegData(from: $0.image) }
        Task {
            do {
                let saved = try await community.saveRecipe(draft, id: existing?.id)
                onSaved(saved)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Новое фото, ещё не отправленное на сервер.
struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage

    init(_ image: UIImage) {
        self.image = image
    }
}

/// Строка ингредиента в редакторе: количество хранится текстом, пока человек печатает.
struct EditableIngredient: Identifiable {
    let id = UUID()
    var name = ""
    var amount = ""
    var unit = MeasureUnit.g.rawValue

    init() {}

    init(_ ingredient: CommunityIngredient) {
        name = ingredient.name
        amount = ingredient.amount.map { AmountText.editable($0) } ?? ""
        unit = ingredient.unit ?? (ingredient.amount == nil ? MeasureUnit.toTaste.rawValue : MeasureUnit.pcs.rawValue)
    }

    var ingredient: CommunityIngredient {
        let value = Double(amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        let hasAmount = (value ?? 0) > 0 && unit != MeasureUnit.toTaste.rawValue
        return CommunityIngredient(name: name,
                                   amount: hasAmount ? value : nil,
                                   unit: hasAmount || unit == MeasureUnit.toTaste.rawValue ? unit : nil)
    }
}

struct EditableStep: Identifiable {
    let id = UUID()
    var text = ""
    var timer = ""

    init() {}

    init(_ step: CommunityStep) {
        text = step.text
        timer = step.timer.map(String.init) ?? ""
    }

    var step: CommunityStep {
        CommunityStep(text: text, timer: Int(timer.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil })
    }
}

enum AmountText {
    /// «1.5» → «1,5» для поля ввода.
    static func editable(_ value: Double) -> String {
        value.rounded() == value
            ? String(Int(value))
            : value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU")))
    }
}

private struct IngredientEditorRow: View {
    @Binding var item: EditableIngredient

    var body: some View {
        HStack(spacing: 8) {
            TextField("Продукт", text: $item.name)
            TextField("Кол-во", text: $item.amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .disabled(item.unit == MeasureUnit.toTaste.rawValue)
            Menu {
                Picker("Единица", selection: $item.unit) {
                    ForEach(MeasureUnit.allCases, id: \.self) { unit in
                        Text(unit.name(for: 5)).tag(unit.rawValue)
                    }
                }
            } label: {
                Text(MeasureUnit(rawValue: item.unit)?.name(for: 5) ?? item.unit)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(minWidth: 44)
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct StepEditorRow: View {
    @Binding var step: EditableStep
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Шаг \(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            TextField("Что сделать", text: $step.text, axis: .vertical)
                .lineLimit(2...6)
            HStack(spacing: 6) {
                Image(systemName: "timer")
                TextField("Таймер, минут (необязательно)", text: $step.timer)
                    .keyboardType(.numberPad)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Миниатюра фото в редакторе с кнопкой удаления.
private struct EditablePhoto<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let onRemove: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 96, height: 96)
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.borderless)
                .padding(4)
                .accessibilityLabel("Убрать фото")
            }
    }
}
