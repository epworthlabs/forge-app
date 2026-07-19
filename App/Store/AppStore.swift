import Foundation
import ForgeCore

struct LoggedSet: Identifiable, Equatable {
    let id = UUID()
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var done: Bool = false
}

struct ExerciseSlot: Identifiable, Equatable {
    let id = UUID()
    var exercise: Exercise
    var targetSets: Int
    var targetReps: Int
    var targetWeightKg: Double
    var lastPerformance: String?
    var sets: [LoggedSet]
}

struct FoodEntry: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var kcal: Int
    var proteinG: Int
    var carbG: Int
    var fatG: Int
}

enum Meal: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snacks = "Snacks"
    var id: String { rawValue }
}

/// In-memory app state — a stand-in for CloudKit persistence (FRG-130/131, not yet built).
/// Screens are being built against this now so they're visually verifiable before the real
/// sync layer lands; swapping the storage underneath shouldn't change any view code.
@MainActor
final class AppStore: ObservableObject {
    @Published var profile: UserProfile
    @Published var program: ProgramTemplate

    @Published var trailingSessions: [WorkoutSession] = []
    @Published var todaysExercises: [ExerciseSlot]
    @Published var restSecondsRemaining: Int = 0

    @Published var mealEntries: [Meal: [FoodEntry]] = [.breakfast: [], .lunch: [], .dinner: [], .snacks: []]
    @Published var bodyweightLogLb: [(date: Date, weightLb: Double)]
    @Published var workoutsCompletedThisWeek = 4
    @Published var workoutsPlannedThisWeek = 5

    @Published var sheetPresented = false

    init(profile: UserProfile, program: ProgramTemplate) {
        self.profile = profile
        self.program = program
        self.bodyweightLogLb = [(Date(), profile.weightKg / 0.45359237)]

        let legDay = ExerciseLibrary.search("Barbell Squat").first
        let rdl = ExerciseLibrary.search("Romanian Deadlift").first
        let legPress = ExerciseLibrary.search("Leg Press").first
        self.todaysExercises = [legDay, rdl, legPress].compactMap { $0 }.enumerated().map { i, ex in
            let targetWeight = 100 + Double(i) * 10
            return ExerciseSlot(exercise: ex, targetSets: 4, targetReps: 8, targetWeightKg: targetWeight,
                                 lastPerformance: nil, sets: (0..<4).map { _ in LoggedSet(weightKg: targetWeight, reps: 8) })
        }
    }

    var currentLoadScore: Double {
        let today = WorkoutSession(date: Date(), sets: todaysExercises.flatMap { slot in
            slot.sets.filter(\.done).map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe) }
        })
        return LoadScoreCalculator.loadScore(today: today, trailingSessions: trailingSessions)
    }

    var nutritionTarget: NutritionTarget {
        NutritionTargetEngine.calculate(profile: profile, loadScore: currentLoadScore)
    }

    var hasTrainingHistory: Bool { !trailingSessions.isEmpty }

    func allFoodEntriesToday() -> [FoodEntry] {
        Meal.allCases.flatMap { mealEntries[$0] ?? [] }
    }

    func totals() -> (kcal: Int, protein: Int, carb: Int, fat: Int) {
        let entries = allFoodEntriesToday()
        return (entries.reduce(0) { $0 + $1.kcal }, entries.reduce(0) { $0 + $1.proteinG },
                entries.reduce(0) { $0 + $1.carbG }, entries.reduce(0) { $0 + $1.fatG })
    }

    func addFood(_ entry: FoodEntry, to meal: Meal) {
        mealEntries[meal, default: []].append(entry)
    }

    func toggleSet(exerciseID: ExerciseSlot.ID, setID: LoggedSet.ID) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }),
              let setIdx = todaysExercises[exIdx].sets.firstIndex(where: { $0.id == setID }) else { return }
        todaysExercises[exIdx].sets[setIdx].done.toggle()
        restSecondsRemaining = todaysExercises[exIdx].sets[setIdx].done ? 105 : restSecondsRemaining
    }

    func updateRPE(exerciseID: ExerciseSlot.ID, setID: LoggedSet.ID, rpe: Double) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }),
              let setIdx = todaysExercises[exIdx].sets.firstIndex(where: { $0.id == setID }) else { return }
        todaysExercises[exIdx].sets[setIdx].rpe = rpe
    }

    func addSet(exerciseID: ExerciseSlot.ID) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let last = todaysExercises[exIdx].sets.last
        todaysExercises[exIdx].sets.append(LoggedSet(weightKg: last?.weightKg ?? 20, reps: last?.reps ?? 8))
    }
}
