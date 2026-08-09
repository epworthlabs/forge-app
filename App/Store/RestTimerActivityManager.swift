import ActivityKit
import Foundation

// Feature request — "I want the rest timer to run as an app notification in the notification
// centre that shows the timer on the lock screen." Companion to `ReminderManager`'s one-shot
// "rest complete" notification: this drives the *live*, ticking-down presentation (Lock Screen +
// Dynamic Island) via ActivityKit. The rendering side lives in the RestTimerWidgetExtension target
// (see RestTimerWidget/RestTimerWidgetLiveActivity.swift) — a Live Activity's UI must be declared
// in a widget extension, it can't be drawn by the main app process, which is why this file only
// starts/updates/ends the Activity rather than rendering anything itself.
@MainActor
final class RestTimerActivityManager {
    static let shared = RestTimerActivityManager()

    private var currentActivity: Activity<RestTimerAttributes>?

    private init() {}

    // Ends any Activity already running (a fresh rest period, not a resumed one — matches
    // `ReminderManager.scheduleRestTimerNotifications`'s remove-then-add pattern) and starts a new
    // one. No-ops quietly if the user has Live Activities disabled system-wide or for this app.
    func start(endDate: Date, exerciseName: String) {
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RestTimerAttributes(exerciseName: exerciseName)
        let state = RestTimerAttributes.ContentState(endDate: endDate)
        currentActivity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: endDate)
        )
    }

    // Called when a workout finishes (`archiveCompletedSession`) or the rest period is otherwise
    // cleared — there's nothing left to count down to, so the Activity shouldn't linger on the
    // Lock Screen until the system eventually expires it on its own.
    func end() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
