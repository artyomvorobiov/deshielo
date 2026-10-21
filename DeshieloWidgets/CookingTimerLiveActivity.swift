import ActivityKit
import SwiftUI
import WidgetKit

/// Таймер готовки на экране блокировки и в Dynamic Island.
struct CookingTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookingTimerAttributes.self) { context in
            LockScreenTimerView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(DeepLink.recipe(context.attributes.recipeID).url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.label, systemImage: "timer")
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(Theme.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 96, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.recipeTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Theme.accent)
            } compactTrailing: {
                Text(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 46)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Theme.accent)
            }
            .widgetURL(DeepLink.recipe(context.attributes.recipeID).url)
            .keylineTint(Theme.accent)
        }
    }
}

private struct LockScreenTimerView: View {
    let attributes: CookingTimerAttributes
    let state: CookingTimerAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(attributes.recipeTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            Text(timerInterval: attributes.startDate...state.endDate, countsDown: true)
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .frame(width: 120, alignment: .trailing)
        }
        .padding(16)
    }
}
