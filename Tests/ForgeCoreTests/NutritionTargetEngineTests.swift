import Testing
import Foundation
@testable import ForgeCore

func makeProfile(goal: Goal = .maintain) -> UserProfile {
    UserProfile(weightKg: 80, heightCm: 178, age: 30, sex: .male, activityLevel: .moderate, goal: goal)
}

@Suite struct NutritionTargetEngineTests {
    @Test func manualMacroSplitOverridesTheDefaultCalculation() {
        var profile = makeProfile(goal: .maintain)
        profile.manualProteinPercent = 0.40
        profile.manualCarbPercent = 0.35
        profile.manualFatPercent = 0.25

        let target = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0)
        let proteinKcal = target.proteinG * 4
        let carbKcal = target.carbG * 4
        let fatKcal = target.fatG * 9

        #expect(abs(proteinKcal / target.calories - 0.40) < 0.01)
        #expect(abs(carbKcal / target.calories - 0.35) < 0.01)
        #expect(abs(fatKcal / target.calories - 0.25) < 0.01)
    }

    @Test func missingAnyOneManualMacroFallsBackToDefault() {
        var profile = makeProfile(goal: .maintain)
        profile.manualProteinPercent = 0.40
        profile.manualCarbPercent = 0.35
        // fat percent left nil — should fall back to the default computed split entirely.
        let target = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0)
        #expect(target.proteinG == profile.weightKg * profile.goal.proteinPerKg)
    }


    @Test func proteinStaysStableAcrossLoadScores() {
        let profile = makeProfile()
        let light = NutritionTargetEngine.calculate(profile: profile, loadScore: 0.5)
        let typical = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0)
        let heavy = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.6)

        #expect(light.proteinG == typical.proteinG)
        #expect(typical.proteinG == heavy.proteinG)
        #expect(typical.proteinG == profile.weightKg * profile.goal.proteinPerKg)
    }

    @Test func calorieAdjustmentScalesWithLoadScore() {
        let profile = makeProfile()
        let typical = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0)
        let heavy = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.4)
        let light = NutritionTargetEngine.calculate(profile: profile, loadScore: 0.6)

        #expect(abs(typical.calorieAdjustment) < 0.01)
        #expect(heavy.calorieAdjustment > 0)
        #expect(light.calorieAdjustment < 0)
    }

    @Test func calorieAdjustmentClippedToTwentyFivePercent() {
        let profile = makeProfile()
        let extreme = NutritionTargetEngine.calculate(profile: profile, loadScore: 10.0)
        let tdeeGoal = TDEECalculator.goalAdjustedTDEE(profile)

        #expect(extreme.calories <= tdeeGoal * 1.25 + 0.01)
    }

    @Test func redSFloorNeverViolated() {
        // Aggressive cut + a very light day should still never drop below the RED-S floor.
        let profile = makeProfile(goal: .cut)
        let result = NutritionTargetEngine.calculate(profile: profile, loadScore: 0.1)

        let floor = 30 * profile.estimatedFatFreeMassKg

        #expect(result.calories >= floor - 0.01)
    }

    @Test func redSFloorDoesNotElevateAnOrdinaryMaintenanceTarget() {
        // Regression: an earlier floor formula folded general daily activity into "exercise
        // expenditure," which pushed the floor above baseline for anyone above sedentary — even
        // with no cut and a perfectly typical Load Score. The floor should only brake aggressive
        // deficits, never inflate a normal day.
        let profile = makeProfile(goal: .maintain)
        let result = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0)
        let tdeeGoal = TDEECalculator.goalAdjustedTDEE(profile)

        #expect(abs(result.calories - tdeeGoal) < 0.01)
        #expect(result.redSFloorApplied == false)
    }

    @Test func macrosAlwaysReconcileToTotalCalories() {
        // Regression: protein anchored at cut-level g/kg plus the full researched carb band can
        // exceed the total calorie target outright — carbs must compress to fit, not silently
        // produce macros that overshoot the stated total.
        for goal: Goal in [.cut, .bulk, .maintain, .recomp] {
            for loadScore in [0.3, 1.0, 1.6] {
                let profile = makeProfile(goal: goal)
                let result = NutritionTargetEngine.calculate(profile: profile, loadScore: loadScore)
                let impliedCalories = result.proteinG * 4 + result.carbG * 4 + result.fatG * 9
                #expect(abs(impliedCalories - result.calories) < 1.0)
            }
        }
    }

    @Test func carbsCompressBeforeProteinOrFatFloorDuringAnAggressiveCut() {
        let profile = makeProfile(goal: .cut)
        let result = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0)

        #expect(result.proteinG == profile.weightKg * profile.goal.proteinPerKg)
        #expect(result.fatG >= 0.55 * profile.weightKg - 0.01)
        #expect(result.carbG < profile.weightKg * NutritionTargetEngine.carbBand(for: 1.0))
    }

    @Test func carbBandSelectionMatchesResearchedRanges() {
        #expect(NutritionTargetEngine.carbBand(for: 0.3) == 4.0)  // light/rest: 3-5 g/kg
        #expect(NutritionTargetEngine.carbBand(for: 1.0) == 6.0)  // moderate: 5-7 g/kg
        #expect(NutritionTargetEngine.carbBand(for: 1.5) == 8.0)  // heavy: 6-10 g/kg
    }
}

@Suite struct ExerciseLibraryTests {
    @Test func loadsTheBundledDataset() {
        #expect(ExerciseLibrary.all.count == 873)
    }

    @Test func searchIsCaseInsensitiveAndMatchesPartialNames() {
        let results = ExerciseLibrary.search("Squat")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.lowercased().contains("squat") })
    }

    @Test func equipmentFilterReturnsOnlyMatchingExercises() {
        let bodyweightOnly = ExerciseLibrary.byEquipment("body only")
        #expect(bodyweightOnly.count == 111)
        #expect(bodyweightOnly.allSatisfy { $0.equipment == "body only" })
    }
}

@Suite struct LoadScoreCalculatorTests {
    @Test func emptyHistoryReturnsBaselineOfOne() {
        let today = WorkoutSession(date: Date(), sets: [SetLog(weightKg: 100, reps: 8, rpe: 8)])
        let score = LoadScoreCalculator.loadScore(today: today, trailingSessions: [])
        #expect(score == 1.0)
    }

    @Test func heavierThanAverageProducesScoreAboveOne() {
        let now = Date()
        let calendar = Calendar.current
        let trailing = (1...4).map { i in
            WorkoutSession(date: calendar.date(byAdding: .day, value: -i * 5, to: now)!,
                            sets: [SetLog(weightKg: 100, reps: 8, rpe: 8)])
        }
        let today = WorkoutSession(date: now, sets: [SetLog(weightKg: 140, reps: 8, rpe: 8)])

        let score = LoadScoreCalculator.loadScore(today: today, trailingSessions: trailing, asOf: now)
        #expect(score > 1.0)
    }

    @Test func missedSessionRevertsScoreToLow() {
        let now = Date()
        let calendar = Calendar.current
        let trailing = (1...4).map { i in
            WorkoutSession(date: calendar.date(byAdding: .day, value: -i * 5, to: now)!,
                            sets: [SetLog(weightKg: 100, reps: 8, rpe: 8)])
        }
        let score = LoadScoreCalculator.loadScore(today: nil, trailingSessions: trailing, asOf: now)
        #expect(score == 0.0)
    }
}
