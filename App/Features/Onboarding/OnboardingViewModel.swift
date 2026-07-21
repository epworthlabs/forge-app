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

extension Sex {
    // Labeled "Sex" rather than "Gender" in the UI — this drives the Mifflin-St Jeor BMR offset
    // term directly (+5 male / -161 female), not a general identity field, and there isn't a
    // third term in that formula to back a third option honestly.
    var displayLabel: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    // Feature request — "the templated programs don't look complete... research 3-4 templates
    // that cater to different classes of gym goers." Previous templates had 1-3 exercises per
    // day (5/3/1 was a single lift, period) — realistic programs for each of these training
    // styles run 4-6. Four distinct classes: a true beginner just starting out, a
    // hypertrophy/bodybuilding-style lifter, a strength/powerlifting-style lifter, and a
    // general-fitness intermediate. Exercise names below are verified exact matches against the
    // bundled free-exercise-db dataset (873 exercises) via a script, not guessed — a typo here
    // would silently produce an empty ExerciseSlot (ExerciseLibrary.search returning no match).
    static let templates: [ProgramTemplate] = [
        // Beginner: a 2-day full-body split alternates A/B every session (the app rotates
        // through `defaultDays` on each Finish Workout), which is what lets "3x/week" actually
        // work out to A-B-A one week, B-A-B the next — standard beginner-program structure.
        ProgramTemplate(id: "beginner-fb", name: "Beginner Full-Body", weekCount: 8, defaultDays: [
            ProgramDay(name: "Full Body A", exercises: [
                ProgramExercise(exerciseName: "Barbell Squat", targetSets: 3, targetReps: 5, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Barbell Bench Press - Medium Grip", targetSets: 3, targetReps: 5, targetWeightKg: 29.48),
                ProgramExercise(exerciseName: "Bent Over Barbell Row", targetSets: 3, targetReps: 8, targetWeightKg: 29.48),
                ProgramExercise(exerciseName: "Standing Military Press", targetSets: 2, targetReps: 8, targetWeightKg: 20.41),
                ProgramExercise(exerciseName: "Cable Crunch", targetSets: 2, targetReps: 12, targetWeightKg: 15.88),
            ]),
            ProgramDay(name: "Full Body B", exercises: [
                ProgramExercise(exerciseName: "Barbell Deadlift", targetSets: 1, targetReps: 5, targetWeightKg: 49.9),
                ProgramExercise(exerciseName: "Barbell Incline Bench Press - Medium Grip", targetSets: 3, targetReps: 8, targetWeightKg: 24.95),
                ProgramExercise(exerciseName: "Chin-Up", targetSets: 3, targetReps: 6, targetWeightKg: 0),
                ProgramExercise(exerciseName: "Dumbbell Shoulder Press", targetSets: 3, targetReps: 8, targetWeightKg: 11.34),
                ProgramExercise(exerciseName: "Barbell Curl", targetSets: 2, targetReps: 10, targetWeightKg: 15.88),
            ]),
        ]),
        // Hypertrophy / bodybuilding style — higher volume, isolation work alongside compounds.
        ProgramTemplate(id: "ppl", name: "Push/Pull/Legs — Hypertrophy", weekCount: 12, defaultDays: [
            ProgramDay(name: "Push", exercises: [
                ProgramExercise(exerciseName: "Barbell Bench Press - Medium Grip", targetSets: 4, targetReps: 8, targetWeightKg: 54.43),
                ProgramExercise(exerciseName: "Barbell Incline Bench Press - Medium Grip", targetSets: 3, targetReps: 10, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Standing Military Press", targetSets: 3, targetReps: 8, targetWeightKg: 34.02),
                ProgramExercise(exerciseName: "Side Lateral Raise", targetSets: 3, targetReps: 15, targetWeightKg: 9.07),
                ProgramExercise(exerciseName: "Triceps Pushdown", targetSets: 3, targetReps: 12, targetWeightKg: 24.95),
                ProgramExercise(exerciseName: "Standing Overhead Barbell Triceps Extension", targetSets: 2, targetReps: 12, targetWeightKg: 15.88),
            ]),
            ProgramDay(name: "Pull", exercises: [
                ProgramExercise(exerciseName: "Barbell Deadlift", targetSets: 3, targetReps: 5, targetWeightKg: 99.79),
                ProgramExercise(exerciseName: "Bent Over Barbell Row", targetSets: 4, targetReps: 8, targetWeightKg: 54.43),
                ProgramExercise(exerciseName: "Wide-Grip Lat Pulldown", targetSets: 3, targetReps: 10, targetWeightKg: 45.36),
                ProgramExercise(exerciseName: "Face Pull", targetSets: 3, targetReps: 15, targetWeightKg: 15.88),
                ProgramExercise(exerciseName: "Barbell Curl", targetSets: 3, targetReps: 10, targetWeightKg: 24.95),
                ProgramExercise(exerciseName: "Hammer Curls", targetSets: 2, targetReps: 12, targetWeightKg: 9.07),
            ]),
            ProgramDay(name: "Legs", exercises: [
                ProgramExercise(exerciseName: "Barbell Squat", targetSets: 4, targetReps: 8, targetWeightKg: 90.72),
                ProgramExercise(exerciseName: "Romanian Deadlift", targetSets: 3, targetReps: 10, targetWeightKg: 70.31),
                ProgramExercise(exerciseName: "Leg Press", targetSets: 3, targetReps: 12, targetWeightKg: 120.2),
                ProgramExercise(exerciseName: "Seated Leg Curl", targetSets: 3, targetReps: 12, targetWeightKg: 34.02),
                ProgramExercise(exerciseName: "Standing Calf Raises", targetSets: 4, targetReps: 15, targetWeightKg: 49.9),
                ProgramExercise(exerciseName: "Leg Extensions", targetSets: 2, targetReps: 15, targetWeightKg: 40.82),
            ]),
        ]),
        // Strength / powerlifting style — Wendler 5/3/1's classic structure (main lift, low reps,
        // 3 weeks building intensity, 4th week deload) plus "Boring But Big"-style assistance
        // work, which real 5/3/1 programs actually include rather than just one lift per day.
        ProgramTemplate(id: "531", name: "5/3/1 for Strength", weekCount: 16, defaultDays: [
            ProgramDay(name: "Squat Day", exercises: [
                ProgramExercise(exerciseName: "Barbell Squat", targetSets: 5, targetReps: 5, targetWeightKg: 79.38),
                ProgramExercise(exerciseName: "Leg Press", targetSets: 5, targetReps: 10, targetWeightKg: 90.72),
                ProgramExercise(exerciseName: "Seated Leg Curl", targetSets: 3, targetReps: 10, targetWeightKg: 29.48),
                ProgramExercise(exerciseName: "Standing Calf Raises", targetSets: 3, targetReps: 15, targetWeightKg: 40.82),
            ]),
            ProgramDay(name: "Bench Day", exercises: [
                ProgramExercise(exerciseName: "Barbell Bench Press - Medium Grip", targetSets: 5, targetReps: 5, targetWeightKg: 58.97),
                ProgramExercise(exerciseName: "Incline Dumbbell Press", targetSets: 5, targetReps: 10, targetWeightKg: 20.41),
                ProgramExercise(exerciseName: "Triceps Pushdown", targetSets: 3, targetReps: 12, targetWeightKg: 20.41),
                ProgramExercise(exerciseName: "Barbell Curl", targetSets: 3, targetReps: 10, targetWeightKg: 20.41),
            ]),
            ProgramDay(name: "Deadlift Day", exercises: [
                ProgramExercise(exerciseName: "Barbell Deadlift", targetSets: 5, targetReps: 5, targetWeightKg: 99.79),
                ProgramExercise(exerciseName: "Bent Over Barbell Row", targetSets: 5, targetReps: 10, targetWeightKg: 45.36),
                ProgramExercise(exerciseName: "Good Morning", targetSets: 3, targetReps: 10, targetWeightKg: 29.48),
                ProgramExercise(exerciseName: "Cable Crunch", targetSets: 3, targetReps: 15, targetWeightKg: 20.41),
            ]),
            ProgramDay(name: "Press Day", exercises: [
                ProgramExercise(exerciseName: "Standing Military Press", targetSets: 5, targetReps: 5, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Seated Cable Rows", targetSets: 5, targetReps: 10, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Side Lateral Raise", targetSets: 3, targetReps: 15, targetWeightKg: 9.07),
                ProgramExercise(exerciseName: "Standing Overhead Barbell Triceps Extension", targetSets: 3, targetReps: 12, targetWeightKg: 15.88),
            ]),
        ], deloadEveryNWeeks: 4),
        // General fitness / intermediate — balanced upper/lower split, moderate volume.
        ProgramTemplate(id: "ul", name: "Upper/Lower — General Fitness", weekCount: 10, defaultDays: [
            ProgramDay(name: "Upper A", exercises: [
                ProgramExercise(exerciseName: "Barbell Bench Press - Medium Grip", targetSets: 4, targetReps: 10, targetWeightKg: 54.43),
                ProgramExercise(exerciseName: "Bent Over Barbell Row", targetSets: 4, targetReps: 10, targetWeightKg: 54.43),
                ProgramExercise(exerciseName: "Standing Military Press", targetSets: 3, targetReps: 12, targetWeightKg: 34.02),
                ProgramExercise(exerciseName: "Wide-Grip Lat Pulldown", targetSets: 3, targetReps: 12, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Barbell Curl", targetSets: 2, targetReps: 12, targetWeightKg: 20.41),
                ProgramExercise(exerciseName: "Triceps Pushdown", targetSets: 2, targetReps: 12, targetWeightKg: 20.41),
            ]),
            ProgramDay(name: "Lower A", exercises: [
                ProgramExercise(exerciseName: "Barbell Squat", targetSets: 4, targetReps: 10, targetWeightKg: 90.72),
                ProgramExercise(exerciseName: "Romanian Deadlift", targetSets: 3, targetReps: 12, targetWeightKg: 70.31),
                ProgramExercise(exerciseName: "Leg Press", targetSets: 3, targetReps: 12, targetWeightKg: 111.13),
                ProgramExercise(exerciseName: "Standing Calf Raises", targetSets: 3, targetReps: 15, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Cable Crunch", targetSets: 2, targetReps: 15, targetWeightKg: 15.88),
            ]),
            ProgramDay(name: "Upper B", exercises: [
                ProgramExercise(exerciseName: "Barbell Incline Bench Press - Medium Grip", targetSets: 4, targetReps: 10, targetWeightKg: 45.36),
                ProgramExercise(exerciseName: "Chin-Up", targetSets: 4, targetReps: 8, targetWeightKg: 0),
                ProgramExercise(exerciseName: "Dumbbell Shoulder Press", targetSets: 3, targetReps: 12, targetWeightKg: 20.41),
                ProgramExercise(exerciseName: "Seated Cable Rows", targetSets: 3, targetReps: 12, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Hammer Curls", targetSets: 2, targetReps: 12, targetWeightKg: 9.07),
                ProgramExercise(exerciseName: "Standing Overhead Barbell Triceps Extension", targetSets: 2, targetReps: 12, targetWeightKg: 15.88),
            ]),
            ProgramDay(name: "Lower B", exercises: [
                ProgramExercise(exerciseName: "Front Squat (Clean Grip)", targetSets: 4, targetReps: 10, targetWeightKg: 58.97),
                ProgramExercise(exerciseName: "Seated Leg Curl", targetSets: 3, targetReps: 12, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Leg Press", targetSets: 3, targetReps: 15, targetWeightKg: 120.2),
                ProgramExercise(exerciseName: "Standing Calf Raises", targetSets: 3, targetReps: 15, targetWeightKg: 40.82),
                ProgramExercise(exerciseName: "Cable Crunch", targetSets: 2, targetReps: 15, targetWeightKg: 15.88),
            ]),
        ]),
    ]

    @Published var step: Int = 1
    @Published var weightLb: Double = 178
    // Feature request — these three used to be hardcoded placeholders (178cm/30/male) at the
    // moment onboarding finished, silently feeding the wrong numbers into every BMR/TDEE
    // calculation from day one. Now real onboarding inputs (AboutYouStep). `sex` starts nil and
    // gates continuing, since a wrong guess there is a real error in the calorie math, not a
    // reasonable default the way an age/height wheel's starting position is.
    @Published var heightCm: Double = 175
    @Published var age: Int = 30
    @Published var sex: Sex?
    @Published var activityLevel: ActivityLevel?
    @Published var goal: Goal?
    // Feature request — "target weight and time period... use those to calculate their daily
    // caloric intake." Only meaningful for cut/bulk (maintain/recomp don't have a literal weight
    // target); nil until the user actually opens the target-weight wheel, so it defaults to
    // whatever `weightLb` was at that point rather than some arbitrary unrelated number.
    @Published var targetWeightLb: Double?
    @Published var targetWeeks: Int = 12
    @Published var selectedProgram: ProgramTemplate?

    var canContinueFromAboutYou: Bool { sex != nil }
    var canContinueFromGoal: Bool { goal != nil }
    var canEnterApp: Bool { selectedProgram != nil }

    /// Onboarding's whole reason for being one flow, not two — this seeds both the program
    /// selection and, via ForgeCore, the baseline nutrition target in a single pass.
    func buildProfile() -> UserProfile? {
        guard let goal, let activityLevel, let sex else { return nil }
        let weightKg = weightLb * 0.45359237
        let hasWeightTarget = goal == .cut || goal == .bulk
        let targetWeightKg = hasWeightTarget ? (targetWeightLb ?? weightLb) * 0.45359237 : nil
        return UserProfile(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex,
                            activityLevel: activityLevel, goal: goal,
                            targetWeightKg: targetWeightKg, targetWeeks: hasWeightTarget ? targetWeeks : nil)
    }
}
