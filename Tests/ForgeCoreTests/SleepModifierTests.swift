import Testing
@testable import ForgeCore

@Suite struct SleepModifierTests {
    @Test func poorSleepDampensAnElevatedLoadScore() {
        let result = SleepModifier.dampen(loadScore: 1.4, sleepHours: 5.5)
        #expect(result.adjustedLoadScore < 1.4)
        #expect(result.adjustedLoadScore > 1.0)
        #expect(result.recoveryFlagged)
    }

    @Test func goodSleepLeavesLoadScoreUntouched() {
        let result = SleepModifier.dampen(loadScore: 1.4, sleepHours: 8.0)
        #expect(result.adjustedLoadScore == 1.4)
        #expect(!result.recoveryFlagged)
    }

    @Test func poorSleepNeverLowersALightDayFurther() {
        // A light/rest day (loadScore <= 1.0) should never be penalized further for poor sleep —
        // the modifier only dampens an already-elevated score, never adds a separate penalty.
        let result = SleepModifier.dampen(loadScore: 0.6, sleepHours: 4.0)
        #expect(result.adjustedLoadScore == 0.6)
        #expect(!result.recoveryFlagged)
    }

    @Test func missingSleepDataLeavesLoadScoreUntouched() {
        let result = SleepModifier.dampen(loadScore: 1.4, sleepHours: nil)
        #expect(result.adjustedLoadScore == 1.4)
        #expect(!result.recoveryFlagged)
    }

    @Test func dampenedScoreNeverDropsBelowOne() {
        // Even at the most extreme Load Score and worst sleep, dampening should pull toward 1.0,
        // never overshoot past it into penalizing the day outright.
        let result = SleepModifier.dampen(loadScore: 3.0, sleepHours: 3.0)
        #expect(result.adjustedLoadScore >= 1.0)
    }
}
