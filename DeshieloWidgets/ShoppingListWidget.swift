import AppIntents
import SwiftUI
import WidgetKit

struct ShoppingEntry: TimelineEntry {
    let date: Date
    let items: [ShoppingItem]
    let remaining: Int

    static let sample = ShoppingEntry(
        date: .now,
        items: [
            ShoppingItem(name: "Сливочное масло", amount: 250, unit: "g", aisle: .dairy),
            ShoppingItem(name: "Картофель", amount: 1, unit: "kg", aisle: .vegetables),
            ShoppingItem(name: "Тимьян", amount: 3, unit: "sprig", aisle: .vegetables),
            ShoppingItem(name: "Красное сухое вино", amount: 750, unit: "ml", aisle: .drinks)
        ],
        remaining: 4
    )
}

struct ShoppingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShoppingEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ShoppingEntry) -> Void) {
        let entry = load()
        completion(context.isPreview && entry.items.isEmpty ? .sample : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShoppingEntry>) -> Void) {
        // Виджет обновляет приложение (при каждом изменении списка) и кнопки самого виджета.
        completion(Timeline(entries: [load()], policy: .never))
    }

    private func load() -> ShoppingEntry {
        let unchecked = ShoppingListStorage.load().unchecked
        return ShoppingEntry(date: .now, items: unchecked, remaining: unchecked.count)
    }
}

struct ShoppingListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.shoppingList, provider: ShoppingProvider()) { entry in
            ShoppingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.surface }
                .widgetURL(DeepLink.shopping.url)
        }
        .configurationDisplayName("Покупки")
        .description("Список покупок под рукой: отмечайте купленное прямо в виджете.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ShoppingWidgetView: View {
    let entry: ShoppingEntry

    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: 10
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack {
                Label("Покупки", systemImage: "cart")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Spacer()
                if entry.remaining > 0 {
                    Text("\(entry.remaining)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Text("Список пуст")
                    .font(.subheadline.weight(.semibold))
                Text("Добавляйте ингредиенты из рецептов")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items.prefix(limit)) { item in
                    Button(intent: ToggleShoppingItemIntent(itemID: item.id.uuidString)) {
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .foregroundStyle(Theme.accent)
                            Text(item.name)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if family != .systemSmall {
                                Text(item.amountText)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .font(family == .systemSmall ? .caption : .subheadline)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if entry.items.count > limit {
                    Text("и ещё \(entry.items.count - limit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
