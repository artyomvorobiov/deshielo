import SwiftUI
import WidgetKit

struct SkeletonEntry: TimelineEntry {
    let date: Date
}

struct SkeletonProvider: TimelineProvider {
    func placeholder(in context: Context) -> SkeletonEntry { SkeletonEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SkeletonEntry) -> Void) {
        completion(SkeletonEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SkeletonEntry>) -> Void) {
        completion(Timeline(entries: [SkeletonEntry(date: .now)], policy: .never))
    }
}

struct SkeletonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Skeleton", provider: SkeletonProvider()) { _ in
            Text(SharedInfo.appName)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Deshielo")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct DeshieloWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SkeletonWidget()
    }
}
