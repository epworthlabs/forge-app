import Foundation
import UserNotifications

/// FRG-306 — local reminders only, no server/push infra. Notifications are scheduled ahead of
/// time (iOS can't evaluate live app state at fire time), then cancelled the moment the user
/// actually logs a workout or a meal — the standard pattern for "remind me if I forget" without a
/// Notification Service Extension.
@MainActor
final class ReminderManager {
    static let shared = ReminderManager()
    private let workoutReminderID = "forge.reminder.workout"
    private let mealReminderID = "forge.reminder.meal"

    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Schedules tonight's reminders (7pm workout, 8pm meal) if not already logged. Call once
    /// reminders are enabled and again each time the app enters background, so "tonight" always
    /// refers to today.
    func scheduleEveningReminders(workoutDone: Bool, mealsLoggedToday: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [workoutReminderID, mealReminderID])

        if !workoutDone {
            center.add(makeRequest(
                id: workoutReminderID, hour: 19, minute: 0,
                title: "Today's workout is still open",
                body: "You haven't logged any sets yet — a quick session beats none."
            ))
        }
        if !mealsLoggedToday {
            center.add(makeRequest(
                id: mealReminderID, hour: 20, minute: 0,
                title: "Nothing logged today",
                body: "Log a meal to keep your nutrition target accurate."
            ))
        }
    }

    func cancelWorkoutReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [workoutReminderID])
    }

    func cancelMealReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [mealReminderID])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [workoutReminderID, mealReminderID])
    }

    private func makeRequest(id: String, hour: Int, minute: Int, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
