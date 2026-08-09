import Foundation

/// Bug fix — "workouts completed not saving day to day, when the day turns over, the workout
/// that's checked off gets unchecked and resets... the calendar under progress is not marking the
/// days off either." Root cause: `AppStore.todaysExercises` (which sets are checked off) only ever
/// lived in memory — the only thing that ever archived it into `trailingSessions` (what the
/// calendar and Today's status tile read) was an explicit "Finish Workout" tap. A cold relaunch
/// rebuilt `todaysExercises` from scratch every time, and a day-boundary crossed while backgrounded
/// silently discarded whatever was checked off. This is what makes that state survive both cases —
/// device-local only, same tradeoff `CustomExerciseStore`/`SyncQueue` already make for their own
/// storage: in-progress session edits never synced to CloudKit even before this existed.
struct WorkoutDraft: Codable {
    var date: Date
    var programDayIndex: Int
    var programWeek: Int
    var exercises: [ExerciseSlot]
    /// Feature request — "the whole workout should be timed." Carried in the draft so a relaunch
    /// mid-workout restores the real elapsed time instead of restarting the clock.
    var startedAt: Date?
}

enum WorkoutDraftStore {
    private static var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workout_draft.json")
    }

    static func load() -> WorkoutDraft? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(WorkoutDraft.self, from: data)
    }

    static func save(_ draft: WorkoutDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: storageURL)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: storageURL)
    }
}
