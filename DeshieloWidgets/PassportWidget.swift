import SwiftUI
import WidgetKit

struct PassportEntry: TimelineEntry {
    let date: Date
    let countries: Int
    let totalCountries: Int
    let dishes: Int
    let flags: [String]
}

struct PassportProvider: TimelineProvider {
    func placeholder(in context: Context) -> PassportEntry {
        PassportEntry(date: .now, countries: 4, totalCountries: 22, dishes: 9, flags: ["🇫🇷", "🇮🇹", "🇯🇵", "🇬🇪"])
    }

    func getSnapshot(in context: Context, completion: @escaping (PassportEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PassportEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .never))
    }

    private func load() -> PassportEntry {
        let catalog = Catalog.bundled
        let summary = PassportSummary(profile: ProfileStorage.load(), catalog: catalog)
        let flags = summary.stamps
            .sorted { $0.value < $1.value }
            .compactMap { catalog.country($0.key)?.flag }
        return PassportEntry(date: .now, countries: summary.countriesCount, totalCountries: summary.totalCountries,
                             dishes: summary.dishesCount, flags: flags)
    }
}

struct PassportWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.passport, provider: PassportProvider()) { entry in
            PassportWidgetView(entry: entry)
                .widgetURL(DeepLink.passport.url)
        }
        .configurationDisplayName("Кулинарный паспорт")
        .description("Сколько стран вы уже «посетили» на своей кухне.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct PassportWidgetView: View {
    let entry: PassportEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.countries), in: 0...Double(max(entry.totalCountries, 1))) {
                Image(systemName: "globe")
            } currentValueLabel: {
                Text("\(entry.countries)")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Кулинарный паспорт")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text("\(entry.countries) из \(entry.totalCountries) стран")
                    .font(.headline)
                Text(RussianPlural.phrase(entry.dishes, "блюдо", "блюда", "блюд"))
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label("Паспорт", systemImage: "globe.europe.africa")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entry.countries)")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                    Text("/\(entry.totalCountries)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(RussianPlural.form(entry.countries, "страна", "страны", "стран"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(entry.flags.isEmpty ? "Приготовьте первое блюдо" : entry.flags.suffix(6).joined())
                    .font(entry.flags.isEmpty ? .caption2 : .body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Theme.parchment }
        }
    }
}
