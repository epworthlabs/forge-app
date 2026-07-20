import Testing
import Foundation
@testable import ForgeCore

@Suite struct WeeklyRecalibrationEngineTests {
    @Test func tooFewWeighInsProducesNoAdjustment() {
        let profile = makeProfile(goal: .cut)
        let now = Date()
        let weighIns: [(date: Date, weightLb: Double)] = [(now, 180), (now.addingTimeInterval(-86400 * 7), 182)]

        let adjustment = WeeklyRecalibrationEngine.recalibratedBaselineAdjustment(profile: profile, weighIns: weighIns, asOf: now)
        #expect(adjustment == 0)
    }

    @Test func losingFasterThanExpectedOnACutRaisesTheBaseline() {
        // A cut expects gradual loss. Losing much faster than the target implies real TDEE is
        // higher than estimated — the correction should raise calories to slow the rate back down.
        // i=0 is "now"; larger i is further in the past, so weight descending as i increases means
        // weight has been dropping as time moves toward "now" — i.e. actively losing.
        let profile = makeProfile(goal: .cut)
        let now = Date()
        let calendar = Calendar.current
        let weighIns: [(date: Date, weightLb: Double)] = (0..<5).map { i in
            (calendar.date(byAdding: .day, value: -i * 3, to: now)!, 180 + Double(i))
        }

        let adjustment = WeeklyRecalibrationEngine.recalibratedBaselineAdjustment(profile: profile, weighIns: weighIns, asOf: now)
        #expect(adjustment > 0)
    }

    @Test func gainingDespiteACutLowersTheBaseline() {
        let profile = makeProfile(goal: .cut)
        let now = Date()
        let calendar = Calendar.current
        let weighIns: [(date: Date, weightLb: Double)] = (0..<5).map { i in
            (calendar.date(byAdding: .day, value: -i * 3, to: now)!, 180 - Double(i))
        }

        let adjustment = WeeklyRecalibrationEngine.recalibratedBaselineAdjustment(profile: profile, weighIns: weighIns, asOf: now)
        #expect(adjustment < 0)
    }

    @Test func driftingOnAMaintainGoalCorrectsOppositeTheDrift() {
        let profile = makeProfile(goal: .maintain)
        let now = Date()
        let calendar = Calendar.current
        // Gaining despite a maintenance target — the recalibration should pull calories down.
        let weighIns: [(date: Date, weightLb: Double)] = (0..<5).map { i in
            (calendar.date(byAdding: .day, value: -i * 3, to: now)!, 180 - Double(i) * 0.5)
        }

        let adjustment = WeeklyRecalibrationEngine.recalibratedBaselineAdjustment(profile: profile, weighIns: weighIns, asOf: now)
        #expect(adjustment < 0)
    }

    @Test func correctionIsBoundedRegardlessOfHowExtremeTheTrend() {
        let profile = makeProfile(goal: .cut)
        let now = Date()
        let calendar = Calendar.current
        // Wildly implausible loss rate — the correction must still stay within the swing cap.
        let weighIns: [(date: Date, weightLb: Double)] = (0..<5).map { i in
            (calendar.date(byAdding: .day, value: -i * 3, to: now)!, 180 + Double(i) * 10)
        }

        let adjustment = WeeklyRecalibrationEngine.recalibratedBaselineAdjustment(profile: profile, weighIns: weighIns, asOf: now)
        let tdeeGoal = TDEECalculator.goalAdjustedTDEE(profile)
        #expect(abs(adjustment) <= 0.15 * tdeeGoal + 0.01)
    }

    @Test func feedsIntoNutritionTargetEngineAsABaselineShift() {
        let profile = makeProfile(goal: .maintain)
        let baseline = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0)
        let recalibrated = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0, weeklyRecalibrationKcal: 150)

        #expect(abs((recalibrated.calories - baseline.calories) - 150) < 0.01)
        #expect(recalibrated.weeklyRecalibrationKcal == 150)
    }
}
