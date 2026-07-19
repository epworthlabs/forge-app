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

    /// TDEE_goal — maintenance adjusted for the user's stated goal, before any Load Score adjustment.
    public static func goalAdjustedTDEE(_ profile: UserProfile) -> Double {
        maintenanceTDEE(profile) * (1 + profile.goal.tdeeAdjustment)
    }
}
