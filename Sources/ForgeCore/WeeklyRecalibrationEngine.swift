import Foundation

/// FRG-301 — MacroFactor-style weekly baseline adjustment layered UNDER the daily Load Score
/// swing: this shifts the goal-adjusted TDEE baseline itself, which Load Score then adjusts
/// around, rather than competing with Load Score for the same daily delta.
///
/// The idea: the calorie target already implies an expected rate of weight change (e.g. a cut's
/// -20% TDEE adjustment implies losing roughly that many calories' worth of body mass per week).
/// If the user's actual logged weight trend is running faster or slower than that implied rate,
/// their real-world TDEE differs from the Mifflin-St Jeor estimate — the baseline gets nudged to
/// close that gap, the same "recalibrate from real outcomes" idea MacroFactor is known for.
public enum WeeklyRecalibrationEngine {
    /// Energy density used to convert a weight-trend discrepancy into a calorie equivalent — the
    /// widely-used ~7700 kcal/kg estimate for adipose tissue (distinct from the RED-S floor, which
    /// IS a literature-cited safety constant; this one is a standard approximation, not a citation).
    static let kcalPerKg: Double = 7700

    /// Fewer than this many weigh-ins in the window is too noisy (day-to-day water/glycogen swings
    /// dwarf a real trend) to safely recalibrate from.
    static let minimumDataPoints = 4

    /// How much of the full calculated correction to apply at once — dampens the swing the same
    /// way Load Score's `k` tuning knob dampens the daily adjustment. Not a cited value; pending
    /// calibration against real adherence/weight-trend data post-launch, same as `k` (PRD Open
    /// Questions).
    public static var dampingFactor: Double = 0.5

    /// Caps the correction relative to TDEE so one noisy week can never move the baseline further
    /// than a full day's Load Score swing could (that swing is clipped to ±25% of TDEE).
    static let maxSwingFraction: Double = 0.15

    /// Returns a calorie/day baseline shift — positive raises the target, negative lowers it.
    /// Zero when there isn't enough trailing weigh-in data to trust a trend.
    public static func recalibratedBaselineAdjustment(
        profile: UserProfile,
        weighIns: [(date: Date, weightLb: Double)],
        asOf referenceDate: Date = Date(),
        windowDays: Int = 14
    ) -> Double {
        let windowStart = Calendar.current.date(byAdding: .day, value: -windowDays, to: referenceDate) ?? referenceDate
        let windowed = weighIns
            .filter { $0.date >= windowStart && $0.date <= referenceDate }
            .sorted { $0.date < $1.date }

        guard windowed.count >= minimumDataPoints, let first = windowed.first, let last = windowed.last else { return 0 }

        let elapsedDays = last.date.timeIntervalSince(first.date) / 86400
        guard elapsedDays >= 3 else { return 0 } // too short a span to distinguish trend from noise

        let actualWeeklyChangeKg = ((last.weightLb - first.weightLb) * 0.45359237) / elapsedDays * 7

        let tdeeGoal = TDEECalculator.goalAdjustedTDEE(profile)
        let expectedDailyDeficitOrSurplus = tdeeGoal * profile.goal.tdeeAdjustment
        let expectedWeeklyChangeKg = (expectedDailyDeficitOrSurplus * 7) / kcalPerKg

        // Losing/gaining faster than the target implies means real TDEE is higher than estimated
        // (or vice versa) — correct in the opposite direction of the discrepancy to pull the
        // actual trend back toward the intended rate.
        let discrepancyKgPerWeek = actualWeeklyChangeKg - expectedWeeklyChangeKg
        let rawCorrectionPerDay = -(discrepancyKgPerWeek * kcalPerKg) / 7

        let dampened = rawCorrectionPerDay * dampingFactor
        let maxSwing = maxSwingFraction * tdeeGoal
        return max(-maxSwing, min(maxSwing, dampened))
    }
}
