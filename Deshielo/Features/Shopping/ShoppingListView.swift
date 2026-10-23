import SwiftUI

/// Список покупок: по отделам магазина или по рецептам, отметки, отправка в сервисы доставки.
struct ShoppingListView: View {
    private enum Grouping: String, CaseIterable, Identifiable {
        case aisles = "По отделам"
        case recipes = "По рецептам"
        var id: String { rawValue }
    }

    @Environment(\.catalog) private var catalog
    @Environment(ShoppingStore.self) private var shopping

    @State private var grouping: Grouping = .aisles
    @State private var newItem = ""
    @State private var showsDelivery = false
    @State private var confirmsClear = false
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                    TextField("Добавить продукт", text: $newItem)
                        .focused($addFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                }
            }

            if shopping.items.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Список пуст", systemImage: "cart")
                    } description: {
                        Text("Добавляйте ингредиенты из рецептов — одинаковые продукты сложатся сами, а список разложится по отделам магазина.")
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    Picker("Группировка", selection: $grouping) {
                        ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            ShoppingRow(item: item) { shopping.toggle(item) }
                        }
                        .onDelete { offsets in
                            shopping.delete(Set(offsets.map { section.items[$0].id }))
                        }
                    }
                }

                if shopping.uncheckedCount > 0 {
                    Section {
                        Button {
                            showsDelivery = true
                        } label: {
                            Label("Заказать продукты с доставкой", systemImage: "shippingbox")
                                .font(.headline)
                        }
                    } footer: {
                        Text("Лавка, Самокат, ВкусВилл, Перекрёсток, Купер, Ozon fresh, Магнит")
                    }
                }
            }
        }
        .navigationTitle("Покупки")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: shopping.shareText()) {
                        Label("Поделиться списком", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        shopping.clearChecked()
                    } label: {
                        Label("Убрать купленное", systemImage: "checkmark.circle")
                    }
                    .disabled(shopping.checkedCount == 0)
                    Button(role: .destructive) {
                        confirmsClear = true
                    } label: {
                        Label("Очистить список", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(shopping.items.isEmpty)
            }
        }
        .confirmationDialog("Очистить весь список?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) { shopping.clearAll() }
        }
        .sheet(isPresented: $showsDelivery) {
            DeliverySheet()
        }
        .sensoryFeedback(.success, trigger: shopping.checkedCount)
    }

    private struct ListSection {
        let title: String
        let items: [ShoppingItem]
    }

    private var sections: [ListSection] {
        let items = shopping.items.sorted { !$0.isChecked && $1.isChecked }
        switch grouping {
        case .aisles:
            return Aisle.allCases.compactMap { aisle in
                let aisleItems = items.filter { $0.aisle == aisle }
                return aisleItems.isEmpty ? nil : ListSection(title: "\(aisle.emoji) \(aisle.title)", items: aisleItems)
            }
        case .recipes:
            var order: [String] = []
            var grouped: [String: [ShoppingItem]] = [:]
            for item in items {
                let title = item.recipeIDs.first.flatMap { catalog.recipe($0)?.title } ?? item.recipeTitle ?? "Без рецепта"
                if grouped[title] == nil { order.append(title) }
                grouped[title, default: []].append(item)
            }
            return order.map { ListSection(title: $0, items: grouped[$0] ?? []) }
        }
    }

    private func addItem() {
        shopping.addCustom(newItem, catalog: catalog)
        newItem = ""
        addFieldFocused = true
    }
}

private struct ShoppingRow: View {
    let item: ShoppingItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Theme.herb : Color.secondary.opacity(0.5))
                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? Color.secondary : Color.primary)
                Spacer()
                Text(item.amountText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
    }
}
