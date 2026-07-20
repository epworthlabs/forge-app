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
    var date: Date = Date()
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

/// FRG-130/131 — backed by CloudKit's private database. State stays in-memory as the source of
/// truth for the UI (every view still just reads `@Published` properties, unchanged); mutating
/// methods update that state immediately and fire off a background CloudKit write, rather than
/// round-tripping through the network before the UI reflects a change.
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

    // FRG-304 — nil until Health sync is enabled and a fetch completes.
    @Published var stepsToday: Int?
    @Published var lastNightSleepHours: Double?

    // FRG-302 — recent/frequent foods, capped and deduped by name+brand, most-recent first.
    @Published private(set) var recentFoods: [FoodSearchResult] = []
    let foodSearchService = FoodSearchService(credentials: Secrets.foodDatabaseCredentials, countryFilter: Secrets.foodDatabaseCountryFilter)

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
        let recalibration = WeeklyRecalibrationEngine.recalibratedBaselineAdjustment(profile: profile, weighIns: bodyweightLogLb)
        return NutritionTargetEngine.calculate(profile: profile, loadScore: currentLoadScore, weeklyRecalibrationKcal: recalibration)
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

    func logFood(_ result: FoodSearchResult, to meal: Meal) {
        let entry = FoodEntry(
            name: result.name,
            kcal: result.kcal,
            proteinG: Int(result.proteinG.rounded()),
            carbG: Int(result.carbG.rounded()),
            fatG: Int(result.fatG.rounded())
        )
        mealEntries[meal, default: []].append(entry)

        recentFoods.removeAll { $0.name == result.name && $0.brand == result.brand }
        recentFoods.insert(result, at: 0)
        if recentFoods.count > 10 { recentFoods.removeLast() }

        // FRG-306 — no-op if no meal reminder is pending (reminders off, or already cancelled).
        ReminderManager.shared.cancelMealReminder()

        Task { try? await CloudKitStore.shared.saveFoodEntry(entry, meal: meal) }
    }

    // FRG-130/131 — appends a new weigh-in; there was previously no UI path that ever grew
    // `bodyweightLogLb` past its single onboarding seed value.
    func logWeight(_ weightLb: Double) {
        let entry = (date: Date(), weightLb: weightLb)
        bodyweightLogLb.append(entry)
        Task { try? await CloudKitStore.shared.saveBodyweightEntry(date: entry.date, weightLb: entry.weightLb) }
    }

    // FRG-130/131 — archives today's completed sets into training history and resets the slate
    // for next time. There was previously no path that ever appended to `trailingSessions`, so
    // Load Score never actually changed session to session for a real user.
    func finishWorkout() {
        let completedSets = todaysExercises.flatMap { slot in
            slot.sets.filter(\.done).map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe) }
        }
        guard !completedSets.isEmpty else { return }

        let session = WorkoutSession(date: Date(), sets: completedSets)
        trailingSessions.append(session)
        workoutsCompletedThisWeek += 1

        for exIdx in todaysExercises.indices {
            for setIdx in todaysExercises[exIdx].sets.indices {
                todaysExercises[exIdx].sets[setIdx].done = false
                todaysExercises[exIdx].sets[setIdx].rpe = nil
            }
        }

        Task { try? await CloudKitStore.shared.saveWorkoutSession(session) }
    }

    // FRG-130/131 — backfills history for a returning user; called once after construction
    // rather than from `init` so the synchronous init never blocks on a network round-trip.
    func loadHistoryFromCloudKit() async {
        async let sessions = try? CloudKitStore.shared.fetchWorkoutSessions()
        async let weighIns = try? CloudKitStore.shared.fetchBodyweightLog()
        async let todaysFood = try? CloudKitStore.shared.fetchFoodEntries(from: Calendar.current.startOfDay(for: Date()), to: Date())

        if let sessions = await sessions, !sessions.isEmpty { trailingSessions = sessions }
        if let weighIns = await weighIns, !weighIns.isEmpty { bodyweightLogLb = weighIns }
        if let todaysFood = await todaysFood { mealEntries = todaysFood }
    }

    // FRG-306 — re-evaluates tonight's reminders against current state; call on toggle-enable and
    // on every app backgrounding so a reminder already satisfied earlier today never re-fires.
    func refreshReminders() {
        let workoutDone = todaysExercises.contains { $0.sets.contains { $0.done } }
        ReminderManager.shared.scheduleEveningReminders(workoutDone: workoutDone, mealsLoggedToday: !allFoodEntriesToday().isEmpty)
    }

    func lookupBarcode(_ code: String) async -> FoodSearchResult? {
        await foodSearchService.lookupBarcode(code)
    }

    func toggleSet(exerciseID: ExerciseSlot.ID, setID: LoggedSet.ID) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }),
              let setIdx = todaysExercises[exIdx].sets.firstIndex(where: { $0.id == setID }) else { return }
        todaysExercises[exIdx].sets[setIdx].done.toggle()
        restSecondsRemaining = todaysExercises[exIdx].sets[setIdx].done ? 105 : restSecondsRemaining
        // FRG-306 — no-op if no workout reminder is pending (reminders off, or already cancelled).
        if todaysExercises[exIdx].sets[setIdx].done { ReminderManager.shared.cancelWorkoutReminder() }
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

    // FRG-304 — refreshes both readouts from HealthKit; safe to call repeatedly (e.g. on
    // foreground) since each fetch is a fresh query, not a subscription.
    func syncHealthKit() async {
        async let steps = HealthKitManager.shared.fetchTodayStepCount()
        async let sleep = HealthKitManager.shared.fetchLastNightSleepHours()
        stepsToday = await steps
        lastNightSleepHours = await sleep
    }
}
