import Foundation
import ForgeCore

extension ActivityLevel {
    var displayLabel: String {
        switch self {
        case .low: return "Low activity"
        case .moderate: return "Moderate activity"
        case .high: return "High activity"
        }
    }
}

extension Goal {
    var displayLabel: String {
        switch self {
        case .bulk: return "Build muscle"
        case .cut: return "Lose fat"
        case .recomp: return "Recomp"
        case .maintain: return "Maintain"
        }
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    // Exercise names below are verified exact matches against the bundled free-exercise-db
    // dataset (873 exercises) — not guessed, since a typo here would silently produce an empty
    // ExerciseSlot (ExerciseLibrary.search returning no match).
    static let templates: [ProgramTemplate] = [
        ProgramTemplate(id: "ppl", name: "Push/Pull/Legs — Strength", weekCount: 12, defaultDays: [
            ProgramDay(name: "Push", exercises: [
                ProgramExercise(exerciseName: "Barbell Bench Press - Medium Grip", targetSets: 4, targetReps: 6, targetWeightKg: 60),
                ProgramExercise(exerciseName: "Standing Military Press", targetSets: 3, targetReps: 8, targetWeightKg: 40),
                ProgramExercise(exerciseName: "Triceps Pushdown", targetSets: 3, targetReps: 12, targetWeightKg: 25),
            ]),
            ProgramDay(name: "Pull", exercises: [
                ProgramExercise(exerciseName: "Barbell Deadlift", targetSets: 3, targetReps: 5, targetWeightKg: 100),
                ProgramExercise(exerciseName: "Bent Over Barbell Row", targetSets: 4, targetReps: 8, targetWeightKg: 60),
                ProgramExercise(exerciseName: "Barbell Curl", targetSets: 3, targetReps: 10, targetWeightKg: 30),
            ]),
            ProgramDay(name: "Legs", exercises: [
                ProgramExercise(exerciseName: "Barbell Squat", targetSets: 4, targetReps: 8, targetWeightKg: 100),
                ProgramExercise(exerciseName: "Romanian Deadlift", targetSets: 3, targetReps: 10, targetWeightKg: 80),
                ProgramExercise(exerciseName: "Leg Press", targetSets: 3, targetReps: 12, targetWeightKg: 140),
            ]),
        ]),
        ProgramTemplate(id: "531", name: "5/3/1 for Beginners", weekCount: 16, defaultDays: [
            ProgramDay(name: "Squat Day", exercises: [ProgramExercise(exerciseName: "Barbell Squat", targetSets: 5, targetReps: 5, targetWeightKg: 80)]),
            ProgramDay(name: "Bench Day", exercises: [ProgramExercise(exerciseName: "Barbell Bench Press - Medium Grip", targetSets: 5, targetReps: 5, targetWeightKg: 60)]),
            ProgramDay(name: "Deadlift Day", exercises: [ProgramExercise(exerciseName: "Barbell Deadlift", targetSets: 5, targetReps: 5, targetWeightKg: 100)]),
            ProgramDay(name: "Press Day", exercises: [ProgramExercise(exerciseName: "Standing Military Press", targetSets: 5, targetReps: 5, targetWeightKg: 40)]),
        ], deloadEveryNWeeks: 4), // 5/3/1's classic structure: 3 weeks building intensity, 4th week deload
        ProgramTemplate(id: "ul", name: "Upper/Lower Hypertrophy", weekCount: 10, defaultDays: [
            ProgramDay(name: "Upper A", exercises: [
                ProgramExercise(exerciseName: "Barbell Bench Press - Medium Grip", targetSets: 4, targetReps: 10, targetWeightKg: 55),
                ProgramExercise(exerciseName: "Bent Over Barbell Row", targetSets: 4, targetReps: 10, targetWeightKg: 55),
                ProgramExercise(exerciseName: "Standing Military Press", targetSets: 3, targetReps: 12, targetWeightKg: 35),
            ]),
            ProgramDay(name: "Lower A", exercises: [
                ProgramExercise(exerciseName: "Barbell Squat", targetSets: 4, targetReps: 10, targetWeightKg: 90),
                ProgramExercise(exerciseName: "Romanian Deadlift", targetSets: 3, targetReps: 12, targetWeightKg: 70),
                ProgramExercise(exerciseName: "Standing Calf Raises", targetSets: 3, targetReps: 15, targetWeightKg: 40),
            ]),
            ProgramDay(name: "Upper B", exercises: [
                ProgramExercise(exerciseName: "Barbell Incline Bench Press - Medium Grip", targetSets: 4, targetReps: 10, targetWeightKg: 45),
                ProgramExercise(exerciseName: "Chin-Up", targetSets: 4, targetReps: 8, targetWeightKg: 0),
                ProgramExercise(exerciseName: "Dumbbell Shoulder Press", targetSets: 3, targetReps: 12, targetWeightKg: 20),
            ]),
            ProgramDay(name: "Lower B", exercises: [
                ProgramExercise(exerciseName: "Front Squat (Clean Grip)", targetSets: 4, targetReps: 10, targetWeightKg: 60),
                ProgramExercise(exerciseName: "Seated Leg Curl", targetSets: 3, targetReps: 12, targetWeightKg: 40),
                ProgramExercise(exerciseName: "Leg Press", targetSets: 3, targetReps: 15, targetWeightKg: 120),
            ]),
        ]),
    ]

    @Published var step: Int = 1
    @Published var weightLb: Double = 178
    @Published var activityLevel: ActivityLevel?
    @Published var goal: Goal?
    @Published var trainingDaysPerWeek: Int?
    @Published var selectedProgram: ProgramTemplate?

    var canContinueFromGoal: Bool { goal != nil }
    var canEnterApp: Bool { selectedProgram != nil }

    func adjustWeight(by delta: Double) {
        weightLb = max(90, weightLb + delta)
    }

    /// Onboarding's whole reason for being one flow, not two — this seeds both the program
    /// selection and, via ForgeCore, the baseline nutrition target in a single pass.
    func buildProfile(heightCm: Double, age: Int, sex: Sex) -> UserProfile? {
        guard let goal, let activityLevel else { return nil }
        let weightKg = weightLb * 0.45359237
        return UserProfile(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex,
                            activityLevel: activityLevel, goal: goal)
    }
}
