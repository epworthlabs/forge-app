import Foundation

/// FRG-305 — PRD Appendix step 5. Poor sleep impairs glucose handling and the anabolic hormonal
/// response: it reduces the body's ability to use extra fuel well, it doesn't raise caloric need.
/// There's no literature supporting an "add X kcal per hour of lost sleep" rule, so this only ever
/// dampens an already-elevated Load Score (a heavy-day increase gets pulled back) — it never adds
/// calories, and it never touches a day that wasn't already trending up.
public enum SleepModifier {
    public struct Result: Sendable, Equatable {
        public var adjustedLoadScore: Double
        public var recoveryFlagged: Bool
    }

    /// Not a cited value — a product tuning knob, same spirit as Load Score's `k`, pending real
    /// calibration data post-launch.
    public static var dampingFactor: Double = 0.5

    public static func dampen(loadScore: Double, sleepHours: Double?, poorSleepThresholdHours: Double = 7.0) -> Result {
        guard let sleepHours, sleepHours < poorSleepThresholdHours, loadScore > 1.0 else {
            return Result(adjustedLoadScore: loadScore, recoveryFlagged: false)
        }
        let dampened = 1.0 + (loadScore - 1.0) * dampingFactor
        return Result(adjustedLoadScore: dampened, recoveryFlagged: true)
    }
}
