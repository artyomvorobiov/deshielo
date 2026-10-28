import SwiftUI
import UIKit

/// Дегустационный дневник: вина и чаи, которые вы пробовали, с фото этикеток и оценками.
struct TastingsView: View {
    @Environment(TastingStore.self) private var tastings

    @State private var filter: Tasting.Kind?
    @State private var editing: TastingDraft?

    private var list: [Tasting] { tastings.tastings(of: DrinksConfig.showsWine ? filter : .tea) }

    var body: some View {
        List {
            if DrinksConfig.showsWine && !tastings.tastings.isEmpty {
                Picker("Показать", selection: $filter) {
                    Text("Всё").tag(Tasting.Kind?.none)
                    ForEach(Tasting.Kind.allCases) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            ForEach(list) { tasting in
                Button {
                    editing = TastingDraft(tasting: tasting, isNew: false)
                } label: {
                    TastingRow(tasting: tasting)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let items = offsets.map { list[$0] }
                for item in items {
                    tastings.delete(item)
                }
            }
        }
        .overlay {
            if list.isEmpty {
                ContentUnavailableView {
                    Label("Пока нет дегустаций", systemImage: "book.closed")
                } description: {
                    Text(DrinksConfig.showsWine
                         ? "Сфотографируйте этикетку вина или пачку чая — приложение прочитает название, а вы добавите оценку и заметки."
                         : "Запишите чай, который попробовали: оценку, ароматы и фото пачки.")
                } actions: {
                    Button("Новая запись") {
                        editing = TastingDraft(tasting: newTasting, isNew: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Дегустации")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = TastingDraft(tasting: newTasting, isNew: true)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Новая дегустация")
            }
        }
        .sheet(item: $editing) { draft in
            TastingEditorView(tasting: draft.tasting, isNew: draft.isNew)
        }
    }

    private var newTasting: Tasting {
        let kind: Tasting.Kind = DrinksConfig.showsWine ? (filter ?? .wine) : .tea
        return Tasting(kind: kind, name: "")
    }
}

/// Что открыть в редакторе: новую запись или существующую.
private struct TastingDraft: Identifiable {
    let tasting: Tasting
    let isNew: Bool

    var id: UUID { tasting.id }
}

/// Записи дневника на странице сорта или чая.
struct TastingList: View {
    let title: String
    let tastings: [Tasting]

    @State private var editing: Tasting?

    var body: some View {
        if !tastings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)
                ForEach(tastings) { tasting in
                    Button {
                        editing = tasting
                    } label: {
                        TastingRow(tasting: tasting)
                            .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $editing) { tasting in
                TastingEditorView(tasting: tasting, isNew: false)
            }
        }
    }
}

struct TastingRow: View {
    let tasting: Tasting

    @Environment(\.drinks) private var drinks

    var body: some View {
        HStack(spacing: 12) {
            cover
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(tasting.displayName.nilIfBlank ?? "Без названия")
                    .font(.headline)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let rating = tasting.rating {
                    RatingStars(value: Double(rating), size: 11)
                }
                if let note = tasting.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts: [String] = []
        switch tasting.kind {
        case .wine:
            if let grape = drinks.grape(tasting.grapeID) {
                parts.append(grape.name)
            } else if let style = drinks.style(tasting.styleID) {
                parts.append(style.name)
            }
        case .tea:
            if let tea = drinks.tea(tasting.teaID), tea.name != tasting.name {
                parts.append(tea.name)
            } else if let type = drinks.teaType(drinks.tea(tasting.teaID)?.type) {
                parts.append(type.name)
            }
        }
        parts.append(tasting.date.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var cover: some View {
        if let name = tasting.photo, let image = JournalPhotos.image(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let tea = drinks.tea(tasting.teaID) {
            DrinkArtwork(tea: tea)
        } else if let grape = drinks.grape(tasting.grapeID) {
            DrinkArtwork(grape: grape)
        } else if let style = drinks.style(tasting.styleID) {
            DrinkArtwork(style: style)
        } else {
            DrinkArtwork(palette: tasting.kind == .wine ? ["#7B1E2E", "#B5485D", "#F3D9DC"] : ["#9C5A1F", "#D9A066", "#F6E7D4"],
                         vessel: tasting.kind == .wine ? .glass : .cup, seed: tasting.id.uuidString)
        }
    }
}

/// Новая запись или правка: фото этикетки с распознаванием названия, оценка, ароматы, заметка.
struct TastingEditorView: View {
    let isNew: Bool

    @Environment(TastingStore.self) private var store
    @Environment(\.drinks) private var drinks
    @Environment(\.dismiss) private var dismiss

    @State private var tasting: Tasting
    @State private var newPhoto: UIImage?
    @State private var removesPhoto = false
    @State private var label: LabelTextParser.Result?
    @State private var isReading = false
    @State private var vintageText: String
    @State private var confirmsDelete = false

    init(tasting: Tasting, isNew: Bool) {
        self.isNew = isNew
        _tasting = State(initialValue: tasting)
        _vintageText = State(initialValue: tasting.vintage.map { String($0) } ?? "")
    }

    private var showsKindPicker: Bool { isNew && DrinksConfig.showsWine }

    var body: some View {
        NavigationStack {
            Form {
                if showsKindPicker {
                    Picker("Что пробуем", selection: $tasting.kind) {
                        ForEach(Tasting.Kind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                photoSection
                nameSection
                if tasting.kind == .wine {
                    wineSection
                } else {
                    teaSection
                }
                Section("Оценка") {
                    StarRatingPicker(rating: ratingBinding)
                        .padding(.vertical, 4)
                }
                aromaSection
                Section("Заметка") {
                    TextField(tasting.kind == .wine ? "Каким было вино, с чем пили" : "Каким был настой, сколько проливов",
                              text: noteBinding, axis: .vertical)
                        .lineLimit(3...6)
                }
                if !isNew {
                    Section {
                        Button("Удалить запись", role: .destructive) {
                            confirmsDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Новая дегустация" : "Дегустация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(tasting.name.nilIfBlank == nil)
                }
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    store.delete(tasting)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Разделы

    private var photoSection: some View {
        Section {
            if let image = currentPhoto {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Button("Убрать фото", role: .destructive) {
                    newPhoto = nil
                    removesPhoto = true
                    label = nil
                }
            } else {
                PhotoSourceButton(onPick: { images in
                    guard let image = images.first else { return }
                    newPhoto = image
                    removesPhoto = false
                    read(image)
                }) {
                    Label(tasting.kind == .wine ? "Сфотографировать этикетку" : "Сфотографировать пачку",
                          systemImage: "camera.viewfinder")
                }
            }
            if isReading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Читаю надписи…")
                        .foregroundStyle(.secondary)
                }
            } else if let label, !label.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Похоже на название — нажмите, чтобы подставить:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(label.suggestions, id: \.self) { text in
                            Chip(title: text, isSelected: tasting.name == text) {
                                tasting.name = text
                            }
                        }
                        if label.suggestions.count > 1 && tasting.name != label.query {
                            Chip(title: label.query, systemImage: "plus") {
                                tasting.name = label.query
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } else if label != nil {
                Text("Не удалось прочитать название — введите его сами.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Фото")
        } footer: {
            Text("Текст распознаётся прямо на телефоне, фото остаётся в вашем дневнике.")
        }
    }

    private var nameSection: some View {
        Section {
            TextField(tasting.kind == .wine ? "Название вина" : "Название чая", text: $tasting.name)
                .textInputAutocapitalization(.words)
            if tasting.kind == .wine {
                TextField("Год урожая", text: $vintageText)
                    .keyboardType(.numberPad)
                if let name = tasting.name.nilIfBlank {
                    VivinoButton(title: "Найти «\(name)» в Vivino", query: name)
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                        .listRowBackground(Color.clear)
                }
            }
        } header: {
            Text("Название")
        } footer: {
            if tasting.kind == .wine {
                Text("В Vivino можно посмотреть оценки и отзывы о конкретном вине — поиск откроется в браузере или в их приложении.")
            }
        }
    }

    private var wineSection: some View {
        Section("Вино") {
            Picker("Стиль", selection: $tasting.styleID) {
                Text("Не выбран").tag(String?.none)
                ForEach(drinks.wine.styles) { style in
                    Text(style.name).tag(Optional(style.id))
                }
            }
            Picker("Сорт", selection: $tasting.grapeID) {
                Text("Не выбран").tag(String?.none)
                ForEach(drinks.wine.grapes) { grape in
                    Text(grape.name).tag(Optional(grape.id))
                }
            }
            Picker("Регион", selection: $tasting.regionID) {
                Text("Не выбран").tag(String?.none)
                ForEach(drinks.wine.regions) { region in
                    Text("\(CountryName.flag(region.country)) \(region.name)").tag(Optional(region.id))
                }
            }
        }
    }

    private var teaSection: some View {
        Section("Чай") {
            Picker("Из чайной карты", selection: $tasting.teaID) {
                Text("Не выбран").tag(String?.none)
                ForEach(drinks.tea.teas) { tea in
                    Text(tea.name).tag(Optional(tea.id))
                }
            }
        }
    }

    private var aromaSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(aromaOptions, id: \.self) { aroma in
                    Chip(title: aroma, isSelected: tasting.aromas.contains(aroma)) {
                        if let index = tasting.aromas.firstIndex(of: aroma) {
                            tasting.aromas.remove(at: index)
                        } else {
                            tasting.aromas.append(aroma)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Ароматы")
        } footer: {
            Text("Подсказки — из описания сорта или чая. Отметьте то, что почувствовали.")
        }
    }

    // MARK: - Данные

    /// Ароматы выбранного сорта или чая, затем общие и уже отмеченные.
    private var aromaOptions: [String] {
        var options: [String] = []
        switch tasting.kind {
        case .wine:
            options += drinks.grape(tasting.grapeID)?.aromas ?? []
            options += ["красные ягоды", "тёмные ягоды", "цитрусы", "яблоко", "цветы", "травы", "пряности",
                        "ваниль", "дуб", "мёд", "минеральность"]
        case .tea:
            options += drinks.tea(tasting.teaID)?.aromas ?? []
            options += ["цветы", "мёд", "фрукты", "орехи", "дымок", "хлеб", "трава", "сухофрукты", "земля"]
        }
        options += tasting.aromas
        var seen: Set<String> = []
        return options.filter { seen.insert($0).inserted }
    }

    private var currentPhoto: UIImage? {
        if let newPhoto { return newPhoto }
        guard !removesPhoto, let name = tasting.photo else { return nil }
        return JournalPhotos.image(named: name)
    }

    private var ratingBinding: Binding<Int> {
        Binding(get: { tasting.rating ?? 0 }, set: { tasting.rating = $0 == 0 ? nil : $0 })
    }

    private var noteBinding: Binding<String> {
        Binding(get: { tasting.note ?? "" }, set: { tasting.note = $0 })
    }

    private func read(_ image: UIImage) {
        isReading = true
        label = nil
        Task {
            let result = await LabelReader.read(image)
            label = result
            isReading = false
            if tasting.name.nilIfBlank == nil, let first = result.suggestions.first {
                tasting.name = first
            }
            if tasting.kind == .wine, vintageText.nilIfBlank == nil, let vintage = result.vintage {
                vintageText = String(vintage)
            }
        }
    }

    private func save() {
        var entry = tasting
        entry.vintage = entry.kind == .wine ? Int(vintageText.trimmingCharacters(in: .whitespaces)) : nil
        if entry.kind == .wine {
            entry.teaID = nil
        } else {
            entry.styleID = nil
            entry.grapeID = nil
            entry.regionID = nil
        }
        if let newPhoto {
            entry.photo = JournalPhotos.save(newPhoto)
        } else if removesPhoto {
            entry.photo = nil
        }
        store.save(entry)
        dismiss()
    }
}
