import ActivityKit
import Foundation

// Feature request — "I want the rest timer to run as an app notification in the notification
// centre that shows the timer on the lock screen." This struct is compiled into BOTH the main
// Forge app target (which starts/updates/ends the Activity from AppStore) and the
// RestTimerWidgetExtension target (which renders it) — ActivityKit requires the exact same
// ActivityAttributes type on both sides of that boundary. Lives here (not under RestTimerWidget/)
// so it's picked up automatically by the Forge target's `App` source path; the widget extension
// target references this single file by its own explicit path in project.yml/project.pbxproj.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        // A Date, not a countdown Int — same reasoning as `AppStore.restEndDate`: the system
        // renders `Text(timerInterval:)` itself from this end time, so the countdown stays correct
        // through backgrounding/locking without this process ticking anything.
        var endDate: Date
    }

    var exerciseName: String
}
