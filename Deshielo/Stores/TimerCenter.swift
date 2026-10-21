import ActivityKit
import AudioToolbox
import Foundation
import Observation
import UserNotifications

struct CookingTimer: Identifiable, Hashable {
    let id: UUID
    let recipeID: String
    let recipeTitle: String
    let label: String
    let startDate: Date
    let endDate: Date
    var activityID: String?

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    func remaining(at date: Date = .now) -> TimeInterval {
        max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(startDate) / duration))
    }
}

/// Таймеры готовки: несколько одновременно, уведомление по окончании
/// и Live Activity в Dynamic Island и на экране блокировки.
@MainActor
@Observable
final class TimerCenter {
    private(set) var timers: [CookingTimer] = []
    /// Последний сработавший таймер — для оповещения внутри приложения.
    var finished: CookingTimer?
    /// Счётчик сработавших таймеров — триггер для вибрации.
    private(set) var finishedCount = 0

    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init() {
        // Live Activity, оставшиеся от прошлого запуска, больше не актуальны.
        LiveActivityController.endAll()
    }

    func timer(label: String, recipeID: String) -> CookingTimer? {
        timers.first { $0.label == label && $0.recipeID == recipeID }
    }

    func start(label: String, minutes: Double, recipe: Recipe) {
        guard minutes > 0 else { return }
        if let existing = timer(label: label, recipeID: recipe.id) {
            cancel(existing)
        }
        let now = Date()
        var timer = CookingTimer(id: UUID(), recipeID: recipe.id, recipeTitle: recipe.title, label: label,
                                 startDate: now, endDate: now.addingTimeInterval(minutes * 60))
        timer.activityID = LiveActivityController.start(timer, palette: recipe.palette)
        timers.append(timer)
        timers.sort { $0.endDate < $1.endDate }
        let scheduled = timer
        Task { await NotificationService.schedule(scheduled) }
        ensureTicking()
    }

    func cancel(_ timer: CookingTimer) {
        timers.removeAll { $0.id == timer.id }
        NotificationService.cancel(timer.id)
        LiveActivityController.end(timer.activityID)
    }

    func cancelAll() {
        for timer in timers { cancel(timer) }
    }

    /// Проверка истёкших таймеров. Вызывается каждую секунду и при возврате в приложение.
    func checkFinished(now: Date = .now) {
        let done = timers.filter { $0.endDate <= now }
        guard !done.isEmpty else { return }
        timers.removeAll { $0.endDate <= now }
        for timer in done {
            LiveActivityController.end(timer.activityID)
        }
        finished = done.last
        finishedCount += done.count
        AudioServicesPlaySystemSound(1005)
    }

    private func ensureTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.checkFinished()
                if self.timers.isEmpty {
                    self.tickTask = nil
                    return
                }
            }
        }
    }
}

enum LiveActivityController {
    static func start(_ timer: CookingTimer, palette: [String]) -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        let attributes = CookingTimerAttributes(recipeID: timer.recipeID, recipeTitle: timer.recipeTitle,
                                                label: timer.label, startDate: timer.startDate, palette: palette)
        let state = CookingTimerAttributes.ContentState(endDate: timer.endDate)
        let content = ActivityContent(state: state, staleDate: timer.endDate.addingTimeInterval(60))
        do {
            let activity = try Activity<CookingTimerAttributes>.request(attributes: attributes, content: content,
                                                                        pushType: nil)
            return activity.id
        } catch {
            return nil
        }
    }

    static func end(_ id: String?) {
        guard let id else { return }
        Task {
            for activity in Activity<CookingTimerAttributes>.activities where activity.id == id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func endAll() {
        Task {
            for activity in Activity<CookingTimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

enum NotificationService {
    static func schedule(_ timer: CookingTimer) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = "Таймер: \(timer.label)"
        content.body = "Готово — \(timer.recipeTitle). Пора переходить к следующему шагу."
        content.sound = .default
        content.userInfo = ["recipeID": timer.recipeID]
        let interval = max(1, timer.endDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: timer.id.uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancel(_ id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
