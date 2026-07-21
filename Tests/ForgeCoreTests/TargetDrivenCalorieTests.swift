import Testing
import Foundation
@testable import ForgeCore

@Suite struct TargetDrivenCalorieTests {
    @Test func noTargetFallsBackToGoalPercentage() {
        let profile = makeProfile(goal: .cut)
        #expect(TDEECalculator.goalAdjustedTDEE(profile) == TDEECalculator.maintenanceTDEE(profile) * (1 + Goal.cut.tdeeAdjustment))
    }

    @Test func targetWeightLossProducesADeficit() {
        var profile = makeProfile(goal: .cut)
        profile.targetWeightKg = profile.weightKg - 4 // lose 4kg
        profile.targetWeeks = 8

        let delta = TDEECalculator.targetDrivenDailyDeltaKcal(profile)
        #expect(delta != nil)
        #expect(delta! < 0)
        // 4kg / 8 weeks = 0.5 kg/week * 7700 / 7 = 550 kcal/day deficit.
        #expect(abs(delta! - (-550)) < 1)
        #expect(TDEECalculator.goalAdjustedTDEE(profile) == TDEECalculator.maintenanceTDEE(profile) + delta!)
    }

    @Test func targetWeightGainProducesASurplus() {
        var profile = makeProfile(goal: .bulk)
        profile.targetWeightKg = profile.weightKg + 2
        profile.targetWeeks = 10

        let delta = TDEECalculator.targetDrivenDailyDeltaKcal(profile)
        #expect(delta! > 0)
    }

    @Test func missingWeeksFallsBackDespiteTargetWeightSet() {
        var profile = makeProfile(goal: .cut)
        profile.targetWeightKg = profile.weightKg - 4
        profile.targetWeeks = nil

        #expect(TDEECalculator.targetDrivenDailyDeltaKcal(profile) == nil)
        #expect(TDEECalculator.goalAdjustedTDEE(profile) == TDEECalculator.maintenanceTDEE(profile) * (1 + Goal.cut.tdeeAdjustment))
    }

    @Test func targetDrivenDeltaIsFixedRegardlessOfLoadScore() {
        var profile = makeProfile(goal: .cut)
        profile.targetWeightKg = profile.weightKg - 4
        profile.targetWeeks = 8

        // The daily-swing layer (Load Score) sits on top of this baseline in
        // NutritionTargetEngine — the baseline itself must not move with it.
        let tdeeGoal = TDEECalculator.goalAdjustedTDEE(profile)
        let light = NutritionTargetEngine.calculate(profile: profile, loadScore: 0.6)
        let heavy = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.4)
        #expect(light.baselineMaintenanceCalories == heavy.baselineMaintenanceCalories)
        #expect(tdeeGoal == TDEECalculator.maintenanceTDEE(profile) + TDEECalculator.targetDrivenDailyDeltaKcal(profile)!)
    }
}
