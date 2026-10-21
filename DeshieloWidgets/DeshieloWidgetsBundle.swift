import SwiftUI
import WidgetKit

@main
struct DeshieloWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecipeOfTheDayWidget()
        ShoppingListWidget()
        PassportWidget()
        CookingTimerLiveActivity()
    }
}
