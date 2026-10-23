import XCTest

/// Обходит основные экраны с демо-данными и делает скриншоты.
/// Заодно это дымовой тест: экраны открываются, приложение не падает.
///
/// Скриншоты прикладываются к отчёту теста (Xcode → Report navigator) — их можно взять для App Store.
/// Если задана переменная окружения SCREENSHOTS_DIR, они сохраняются ещё и PNG-файлами в эту папку.
/// При запуске через xcodebuild переменную передают как TEST_RUNNER_SCREENSHOTS_DIR — так делает CI.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testScreens() {
        launch()
        snap("01-today")
        app.swipeUp()
        snap("02-today-more")
        app.swipeUp()
        snap("03-today-end")

        openLink("deshielo://recipe/beef-wellington")
        snap("04-recipe")
        app.swipeUp()
        snap("05-recipe-ingredients")
        app.swipeUp()
        app.swipeUp()
        snap("06-recipe-steps")

        openLink("deshielo://recipe/tuhu")
        snap("07-history-recipe")
        app.swipeUp()
        snap("08-history-source")

        openLink("deshielo://cook/carbonara")
        snap("09-cooking")
        app.swipeLeft()
        snap("10-cooking-step")
        tapIfExists(app.buttons["Закрыть режим готовки"])

        selectTab("Рецепты")
        snap("11-explore")
        app.swipeUp()
        snap("12-explore-list")
        app.swipeDown()
        app.swipeDown()
        if tapElement(containing: "Высокая кухня") {
            snap("13-collection")
            goBack()
        }

        selectTab("Покупки")
        snap("14-shopping")
        if tapElement(containing: "Заказать продукты") {
            snap("15-delivery")
            tapIfExists(app.buttons["Готово"])
        }

        selectTab("Моё")
        snap("16-profile")
        let rows = [
            ("Дневник готовки", "17-journal"),
            ("Меню на неделю", "18-meal-plan"),
            ("Из холодильника", "19-fridge"),
            ("Конвертер мер", "20-converter"),
            ("Машина времени", "21-time-machine"),
            ("Карта вкусов", "22-map")
        ]
        for (title, name) in rows where tapElement(containing: title) {
            snap(name, delay: name == "22-map" ? 4 : 1)
            goBack()
        }

        openLink("deshielo://passport")
        snap("23-passport")

        selectTab("Сообщество")
        snap("24-community")
        if tapElement(containing: "Тыквенный суп") {
            snap("25-community-recipe")
            if scrollTo("Как получилось у других") {
                snap("26-community-reviews")
            }
            goBack()
        }
        tapIfExists(app.buttons["Новый рецепт"])
        snap("27-recipe-editor")
        tapIfExists(app.buttons["Отмена"])
        tapIfExists(app.buttons["Аккаунт сообщества"])
        snap("28-community-account")
        goBack()

        openLink("deshielo://recipe/syrniki")
        if scrollTo("Как получилось у других") {
            snap("29-catalog-reviews")
            if tapElement(containing: "Оценить и показать своё фото") {
                snap("36-review-composer")
                tapIfExists(app.buttons["Отмена"])
            }
        }
    }

    @MainActor
    func testDarkScreens() {
        launch(dark: true)
        snap("30-dark-today")
        openLink("deshielo://recipe/tuhu")
        snap("31-dark-history-recipe")
        openLink("deshielo://recipe/spherified-olives")
        snap("32-dark-recipe")
        openLink("deshielo://cook/beef-wellington")
        snap("33-dark-cooking")
        tapIfExists(app.buttons["Закрыть режим готовки"])
        selectTab("Покупки")
        snap("34-dark-shopping")
        selectTab("Сообщество")
        snap("35-dark-community")
    }

    // MARK: - Помощники

    @MainActor
    private func launch(dark: Bool = false) {
        app = XCUIApplication()
        // Русская локаль симулятора — чтобы и карта, и системные подписи на скриншотах были на русском.
        app.launchArguments = ["-DemoData", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
            + (dark ? ["-DemoDark"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Приложение не показало вкладки")
    }

    @MainActor
    private func snap(_ name: String, delay: TimeInterval = 1) {
        // Даём закончиться анимациям переходов.
        Thread.sleep(forTimeInterval: delay)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"], !directory.isEmpty else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func openLink(_ string: String) {
        guard let url = URL(string: string) else { return }
        app.open(url)
        _ = app.wait(for: .runningForeground, timeout: 10)
    }

    @MainActor
    private func selectTab(_ title: String) {
        let button = app.tabBars.buttons[title]
        guard button.waitForExistence(timeout: 5) else {
            XCTFail("Нет вкладки «\(title)»")
            return
        }
        button.tap()
    }

    /// Нажимает на первый элемент, в подписи которого есть текст.
    /// Если его не видно или он под панелью вкладок — прокручивает экран.
    @MainActor
    @discardableResult
    private func tapElement(containing text: String) -> Bool {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
        var swipes = 0
        while !isReachable(element) && swipes < 5 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        guard isReachable(element) else {
            XCTFail("Не найден элемент «\(text)»")
            return false
        }
        element.tap()
        return true
    }

    /// Прокручивает экран, пока не покажется текст. Возвращает false, если не нашёл.
    @MainActor
    private func scrollTo(_ text: String) -> Bool {
        let element = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        var swipes = 0
        while !isReachable(element) && swipes < 14 {
            app.swipeUp()
            swipes += 1
        }
        guard isReachable(element) else {
            XCTFail("Не найден текст «\(text)»")
            return false
        }
        return true
    }

    /// Элемент на экране и не закрыт плавающей панелью вкладок: иначе нажатие достанется ей.
    @MainActor
    private func isReachable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let tabBar = app.tabBars.firstMatch
        return !tabBar.exists || element.frame.maxY <= tabBar.frame.minY
    }

    @MainActor
    private func tapIfExists(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 3) {
            element.tap()
        }
    }

    @MainActor
    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 3) {
            back.tap()
        }
    }
}
