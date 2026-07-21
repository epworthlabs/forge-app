import Foundation

/// PRD Appendix step 1 — Mifflin-St Jeor baseline, active from onboarding before any training data exists.
public enum TDEECalculator {
    public static func bmr(_ profile: UserProfile) -> Double {
        let base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age)
        switch profile.sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    public static func maintenanceTDEE(_ profile: UserProfile) -> Double {
        bmr(profile) * profile.activityLevel.multiplier
    }

    /// Energy density used to convert a target weight change into a daily calorie delta — the
    /// same ~7700 kcal/kg estimate WeeklyRecalibrationEngine uses for the analogous conversion.
    static let kcalPerKg: Double = 7700

    /// Feature request — "target weight and time period... use those to calculate their daily
    /// caloric intake." Derived once from `profile.weightKg` (the anchor set at onboarding or
    /// whenever target/timeframe were last changed) and `profile.targetWeightKg`/`targetWeeks` —
    /// not from today's logged weight or today's date, which is what keeps the result fixed until
    /// the user explicitly changes one of those three inputs, rather than drifting day to day.
    static func targetDrivenDailyDeltaKcal(_ profile: UserProfile) -> Double? {
        guard let targetWeightKg = profile.targetWeightKg, let targetWeeks = profile.targetWeeks, targetWeeks > 0 else { return nil }
        let weeklyChangeKg = (targetWeightKg - profile.weightKg) / Double(targetWeeks)
        return weeklyChangeKg * kcalPerKg / 7
    }

    /// TDEE_goal — maintenance adjusted for the user's stated goal, before any Load Score
    /// adjustment. Uses the target-weight/timeframe-derived delta when both are set; falls back
    /// to Goal's fixed percentage otherwise (maintain/recomp, or a profile predating this field).
    public static func goalAdjustedTDEE(_ profile: UserProfile) -> Double {
        if let delta = targetDrivenDailyDeltaKcal(profile) {
            return maintenanceTDEE(profile) + delta
        }
        return maintenanceTDEE(profile) * (1 + profile.goal.tdeeAdjustment)
    }
}
