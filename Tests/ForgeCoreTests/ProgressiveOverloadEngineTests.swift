import Testing
@testable import ForgeCore

@Suite struct ProgressiveOverloadEngineTests {
    @Test func hittingTargetRepsWithRoomLeftIncreasesLoad() {
        let suggestion = ProgressiveOverloadEngine.suggestNextSet(lastWeightKg: 100, lastReps: 8, lastRPE: 7, targetReps: 8)
        #expect(suggestion.weightKg > 100)
        #expect(suggestion.reps == 8)
    }

    @Test func hittingTargetRepsAtHighRPEHoldsTheLoad() {
        let suggestion = ProgressiveOverloadEngine.suggestNextSet(lastWeightKg: 100, lastReps: 8, lastRPE: 9, targetReps: 8)
        #expect(suggestion.weightKg == 100)
        #expect(suggestion.reps == 8)
    }

    @Test func missingTargetRepsReducesTheLoad() {
        let suggestion = ProgressiveOverloadEngine.suggestNextSet(lastWeightKg: 100, lastReps: 5, lastRPE: 9, targetReps: 8)
        #expect(suggestion.weightKg < 100)
    }

    @Test func suggestionsRoundToTheNearestPlateIncrement() {
        let suggestion = ProgressiveOverloadEngine.suggestNextSet(lastWeightKg: 101, lastReps: 8, lastRPE: 7, targetReps: 8)
        #expect(suggestion.weightKg.truncatingRemainder(dividingBy: 2.5) == 0)
    }

    @Test func missingRPEDefaultsToATypicalWorkingEffort() {
        // No RPE logged — should behave like RPE 8 (the same default the rest of the engine uses).
        let withDefault = ProgressiveOverloadEngine.suggestNextSet(lastWeightKg: 100, lastReps: 8, lastRPE: nil, targetReps: 8)
        let withExplicit8 = ProgressiveOverloadEngine.suggestNextSet(lastWeightKg: 100, lastReps: 8, lastRPE: 8, targetReps: 8)
        #expect(withDefault == withExplicit8)
    }
}
