import Foundation
import ForgeCore

/// Codable stand-in for `AppStore.bodyweightLogLb`'s `(date, weightLb)` tuples — tuples can't
/// conform to Codable, and this history now round-trips through both the local mirror below and
/// CloudKit's bodyweight blob record.
struct BodyweightEntry: Codable {
    var date: Date
    var weightLb: Double
}

/// Canonical "which calendar day is this" key (local timezone), shared by CloudKit's per-day
/// FoodDay record names and the local mirror below — one definition, so the two storage layers
/// can never disagree about where a day boundary falls.
enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(for date: Date) -> String { formatter.string(from: date) }
    static var today: String { string(for: Date()) }
}

/// Root-cause fix — "when a new day rolls over, the workouts I completed are no longer marked
/// completed / the weight I log is no longer recorded / my recipe isn't there anymore."
///
/// History (sessions, weigh-ins, today's food) previously lived *only* in `AppStore`'s memory
/// between CloudKit round-trips — and every CloudKit *read* was silently failing (see
/// `CloudKitStore`'s header for that half of the root cause), so any cold launch started from
/// nothing. This is the device-local mirror: written on every mutation, loaded synchronously in
/// `AppStore.init`, so a relaunch/rollover never depends on a network fetch succeeding at all.
/// CloudKit remains the reinstall/cross-device layer on top — this file is what guarantees the
/// same-device case even when iCloud is signed out, restricted, or briefly unreachable.
enum LocalHistoryStore {
    struct Snapshot: Codable {
        var sessions: [WorkoutSession]
        var weighIns: [BodyweightEntry]
        /// Which calendar day `meals` belongs to — a stale day's meals must not leak into a new
        /// day, so the loader only applies `meals` when this still matches today.
        var mealsDayKey: String
        var meals: [Meal: [FoodEntry]]
    }

    private static var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("local_history.json")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storageURL)
    }

    // Feature request — "reset their profile." Drops the local mirror so a relaunch after reset
    // doesn't repopulate history from this device's own cache.
    static func clear() {
        try? FileManager.default.removeItem(at: storageURL)
    }
}
