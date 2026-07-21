import Foundation

struct ProgramExercise: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var exerciseName: String
    var targetSets: Int
    var targetReps: Int
    var targetWeightKg: Double
}

struct ProgramDay: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var exercises: [ProgramExercise]
}

/// FRG-104 — previously carried no exercise content at all (just id/name/daysPerWeek/weeks), so
/// `AppStore` hardcoded the same 3 exercises regardless of which program was selected.
///
/// Feature request — "editable timeframe... customize or copy over to future weeks" needed a
/// second pass on this model: `weekCount` is the editable timeframe, `defaultDays` is what every
/// week uses unless explicitly customized, and `weekOverrides` holds only the weeks that
/// genuinely differ (1-indexed). This is deliberately sparse rather than a full `[ProgramWeek]`
/// array — the common case (a program that repeats the same split every week) shouldn't have to
/// store N duplicate copies of the same day list, and "copy week 3 to future weeks" is just
/// writing entries into this dictionary.
struct ProgramTemplate: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var weekCount: Int
    var defaultDays: [ProgramDay]
    var weekOverrides: [Int: [ProgramDay]] = [:]
    // FRG-206 — nil means no scheduled deloads (the default; not exposed in the editor UI yet).
    var deloadEveryNWeeks: Int? = nil

    /// 1-indexed week number. Out-of-range weeks (program ran longer than its own timeframe)
    /// clamp to the last defined week rather than crash or return empty.
    func days(forWeek week: Int) -> [ProgramDay] {
        let clamped = max(1, min(week, weekCount))
        return weekOverrides[clamped] ?? defaultDays
    }

    var daysPerWeek: Int { defaultDays.count }
    var meta: String { "\(daysPerWeek) days/wk · \(weekCount) weeks" }
}
