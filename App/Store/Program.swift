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
/// `AppStore` hardcoded the same 3 exercises regardless of which program was selected. `days` is
/// what actually drives `todaysExercises` now — for both the 3 curated templates and any
/// user-built custom program, so the distinction between them is invisible past selection time.
struct ProgramTemplate: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var weeks: Int
    var days: [ProgramDay]
    // FRG-206 — nil means no scheduled deloads (the default for custom programs, which don't
    // expose this in the builder UI yet). 5/3/1's classic structure has a deload every 4th week
    // built in, so the curated template sets this explicitly.
    var deloadEveryNWeeks: Int? = nil

    var daysPerWeek: Int { days.count }
    var meta: String { "\(daysPerWeek) days/wk · \(weeks) weeks" }
}
