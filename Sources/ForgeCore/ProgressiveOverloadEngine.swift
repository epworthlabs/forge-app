import Foundation

/// FRG-113 — a suggestion, never an auto-applied change: the PRD is explicit that the user can
/// accept or override.
public enum ProgressiveOverloadEngine {
    public struct Suggestion: Sendable, Equatable {
        public var weightKg: Double
        public var reps: Int
    }

    /// Hit target reps at RPE ≤ 8 (real room left) → +5%, rounded to the nearest plate increment.
    /// Hit target reps but already at RPE 8.5+ → hold the load, same target reps — pushing
    /// further risks form breakdown on the very next attempt. Missed target reps → −10%, so the
    /// next attempt is actually achievable rather than repeating a failed rep count at the same
    /// load.
    ///
    /// Feature request — "increase by increments of 5 or 2.5lbs, depending on the exercise."
    /// `roundingIncrementKg` is caller-supplied (the app layer picks 5lb-in-kg for barbell work,
    /// 2.5lb-in-kg otherwise, based on `Exercise.equipment`) rather than hardcoded here — ForgeCore
    /// doesn't know about lb/kg display preference, just "round to this increment." Default kept
    /// at the original 2.5kg for any caller that doesn't care.
    public static func suggestNextSet(lastWeightKg: Double, lastReps: Int, lastRPE: Double?, targetReps: Int, roundingIncrementKg: Double = 2.5) -> Suggestion {
        let rpe = lastRPE ?? 8
        guard lastReps >= targetReps else {
            return Suggestion(weightKg: roundToIncrement(lastWeightKg * 0.9, increment: roundingIncrementKg), reps: targetReps)
        }
        guard rpe <= 8 else {
            return Suggestion(weightKg: lastWeightKg, reps: targetReps)
        }
        return Suggestion(weightKg: roundToIncrement(lastWeightKg * 1.05, increment: roundingIncrementKg), reps: targetReps)
    }

    private static func roundToIncrement(_ weightKg: Double, increment: Double) -> Double {
        (weightKg / increment).rounded() * increment
    }
}
