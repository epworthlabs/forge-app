import Foundation

public struct NutritionTarget: Sendable, Equatable {
    public var calories: Double
    public var proteinG: Double
    public var carbG: Double
    public var fatG: Double

    // Explainability breakdown for the Target Explanation sheet (PRD FRG-207/211).
    public var baselineMaintenanceCalories: Double
    public var loadScore: Double
    public var calorieAdjustment: Double
    public var redSFloorApplied: Bool
    /// FRG-301 — weekly weight-trend recalibration already folded into this baseline; broken out
    /// separately here so the explanation sheet can show it as its own line, distinct from today's
    /// Load Score swing.
    public var weeklyRecalibrationKcal: Double
}

public enum NutritionTargetEngine {
    /// How aggressively calories swing with Load Score. Not a cited literature value — a product
    /// tuning knob (PRD Appendix step 3), calibrated here to roughly match the design prototype's
    /// worked example (2,500 kcal baseline, 1.4× Load Score → +180 kcal) pending real usage data.
    public static var k: Double = 0.18

    public static func calculate(profile: UserProfile, loadScore: Double, weeklyRecalibrationKcal: Double = 0) -> NutritionTarget {
        // FRG-301 — weekly recalibration shifts the baseline itself; Load Score's daily swing
        // then applies on top of that shifted baseline, per the PRD's "layer on top of" framing.
        let tdeeGoal = TDEECalculator.goalAdjustedTDEE(profile) + weeklyRecalibrationKcal

        let rawAdjustment = tdeeGoal * k * (loadScore - 1.0)
        let clippedAdjustment = max(-0.25 * tdeeGoal, min(0.25 * tdeeGoal, rawAdjustment))
        let candidateCalories = tdeeGoal + clippedAdjustment

        // RED-S floor: intake must never imply Energy Availability < 30 kcal/kg fat-free mass.
        // Deliberately NOT (TDEE_goal - BMR) here — that delta includes general daily activity via
        // the activity multiplier, not just structured exercise, and would push this floor above
        // baseline for almost anyone above "sedentary." Without a real per-session kcal-burned
        // estimate to use as exercise expenditure specifically, this simplifies to intake/FFM alone,
        // which only engages as a brake during aggressive cuts — not as a floor under every target.
        let redSFloor = 30 * profile.estimatedFatFreeMassKg

        let finalCalories = max(candidateCalories, redSFloor)
        let floorApplied = finalCalories > candidateCalories

        let proteinG: Double
        let carbG: Double
        let fatG: Double
        if let proteinPct = profile.manualProteinPercent, let carbPct = profile.manualCarbPercent, let fatPct = profile.manualFatPercent {
            // Feature request — "adjust the target macro splits manually if needed." A percentage
            // split of whatever the total is, so it still scales with the daily Load Score swing
            // instead of pinning fixed gram targets against a calorie total that moves day to day.
            proteinG = (finalCalories * proteinPct) / 4
            carbG = (finalCalories * carbPct) / 4
            fatG = (finalCalories * fatPct) / 9
        } else {
            // Protein is the fixed anchor (PRD Appendix step 4) and fat has a hard floor for
            // hormonal health, so carbs are the one macro allowed to flex: give them the full
            // researched g/kg band when the calorie budget allows it, but compress them — never
            // protein, never below the fat floor — when it doesn't. Without this, protein + the
            // full carb band can exceed the total target outright during a cut, and the three
            // macros silently stop summing to it.
            let defaultProteinG = profile.weightKg * profile.goal.proteinPerKg
            let proteinKcal = defaultProteinG * 4
            let fatFloorG = 0.55 * profile.weightKg
            let fatFloorKcal = fatFloorG * 9
            let desiredCarbKcal = profile.weightKg * carbBand(for: loadScore) * 4

            let kcalAvailableForCarbs = max(0, finalCalories - proteinKcal - fatFloorKcal)
            let carbKcal = min(desiredCarbKcal, kcalAvailableForCarbs)

            let kcalRemainingForFat = finalCalories - proteinKcal - carbKcal
            proteinG = defaultProteinG
            carbG = carbKcal / 4
            fatG = max(fatFloorG, kcalRemainingForFat / 9)
        }

        return NutritionTarget(
            calories: finalCalories,
            proteinG: proteinG,
            carbG: carbG,
            fatG: fatG,
            baselineMaintenanceCalories: TDEECalculator.maintenanceTDEE(profile),
            loadScore: loadScore,
            calorieAdjustment: finalCalories - tdeeGoal,
            redSFloorApplied: floorApplied,
            weeklyRecalibrationKcal: weeklyRecalibrationKcal
        )
    }

    /// PRD Appendix step 4 — 3–5 / 5–7 / 6–10 g/kg by training intensity, using the band midpoint.
    static func carbBand(for loadScore: Double) -> Double {
        switch loadScore {
        case ..<0.7: return 4.0
        case 0.7..<1.3: return 6.0
        default: return 8.0
        }
    }
}
