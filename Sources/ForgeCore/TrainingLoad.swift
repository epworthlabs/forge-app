import Foundation

public struct SetLog: Sendable {
    public var weightKg: Double
    public var reps: Int
    /// RPE input is a first-class part of the logging UI (PRD FRG-110) — optional here only to
    /// tolerate missing/imported data. Defaults to 8 (a typical working-set effort) rather than 10,
    /// so an absent value doesn't silently read as max effort.
    public var rpe: Double?

    public init(weightKg: Double, reps: Int, rpe: Double? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
    }

    var effortFactor: Double { (rpe ?? 8) / 10 }
}

public struct WorkoutSession: Sendable {
    public var date: Date
    public var sets: [SetLog]

    public init(date: Date, sets: [SetLog]) {
        self.date = date
        self.sets = sets
    }

    /// Σ(sets × reps × weight × RPE/10) — PRD Appendix step 2.
    public var volumeLoad: Double {
        sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg * $1.effortFactor }
    }
}

public enum LoadScoreCalculator {
    /// LoadScore = today's volume load ÷ trailing 28-day average — relative to the user's own
    /// history, never a fixed universal threshold (PRD Appendix step 2).
    public static func loadScore(today: WorkoutSession?, trailingSessions: [WorkoutSession], asOf referenceDate: Date = Date()) -> Double {
        let windowStart = Calendar.current.date(byAdding: .day, value: -28, to: referenceDate) ?? referenceDate
        let windowed = trailingSessions.filter { $0.date >= windowStart && $0.date < referenceDate }

        guard !windowed.isEmpty else { return 1.0 }
        let average = windowed.reduce(0) { $0 + $1.volumeLoad } / Double(windowed.count)
        guard average > 0 else { return 1.0 }

        let todayLoad = today?.volumeLoad ?? 0
        return todayLoad / average
    }
}
