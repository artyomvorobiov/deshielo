import ActivityKit
import Foundation

/// Данные Live Activity таймера готовки (Dynamic Island и экран блокировки).
struct CookingTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
    }

    var recipeID: String
    var recipeTitle: String
    var label: String
    var startDate: Date
    var palette: [String]
}
