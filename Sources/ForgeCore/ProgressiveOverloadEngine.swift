import Foundation

/// FRG-113 — a suggestion, never an auto-applied change: the PRD is explicit that the user can
/// accept or override.
public enum ProgressiveOverloadEngine {
    public struct Suggestion: Sendable, Equatable {
        public var weightKg: Double
        public var reps: Int
    }

    /// Hit target reps at RPE ≤ 8 (real room left) → +5%, rounded to the nearest 2.5kg plate
    /// increment. Hit target reps but already at RPE 8.5+ → hold the load, same target reps —
    /// pushing further risks form breakdown on the very next attempt. Missed target reps → −10%,
    /// so the next attempt is actually achievable rather than repeating a failed rep count at the
    /// same load.
    public static func suggestNextSet(lastWeightKg: Double, lastReps: Int, lastRPE: Double?, targetReps: Int) -> Suggestion {
        let rpe = lastRPE ?? 8
        guard lastReps >= targetReps else {
            return Suggestion(weightKg: roundToPlate(lastWeightKg * 0.9), reps: targetReps)
        }
        guard rpe <= 8 else {
            return Suggestion(weightKg: lastWeightKg, reps: targetReps)
        }
        return Suggestion(weightKg: roundToPlate(lastWeightKg * 1.05), reps: targetReps)
    }

    private static func roundToPlate(_ weightKg: Double) -> Double {
        (weightKg / 2.5).rounded() * 2.5
    }
}
