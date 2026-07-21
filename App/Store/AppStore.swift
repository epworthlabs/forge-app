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

struct FoodEntry: Identifiable, Equatable, Codable {
    let id = UUID()
    var date: Date = Date()
    var name: String
    var kcal: Int
    var proteinG: Int
    var carbG: Int
    var fatG: Int
}

enum Meal: String, CaseIterable, Identifiable, Codable {
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
    // Feature request — "select which workout program they want to do, especially if they have
    // multiple." The library of programs a user has built/picked; `program` is whichever one of
    // these is currently active. Always contains `program` itself (enforced in `init` and every
    // mutating method below), so a ProgramSelectionView tile grid never has to special-case it.
    @Published var savedPrograms: [ProgramTemplate]
    // FRG-104 — which of program.days is "today." Programs with more than one day rotate by
    // session (advances on Finish Workout), not by calendar date — there's no weekly-schedule
    // concept (e.g. "Push is always Monday") in this app, matching how most non-calendar-locked
    // splits (PPL, Upper/Lower) actually get run in practice.
    @Published var currentProgramDayIndex: Int
    // FRG-206 — when the program started, so "which week are we in" (and therefore "is this a
    // scheduled deload week") can be computed without a separate week counter that could drift
    // out of sync with actual elapsed time.
    @Published var programStartDate: Date

    @Published var trailingSessions: [WorkoutSession] = []
    @Published var todaysExercises: [ExerciseSlot]
    // FRG-111 — a Date, not a countdown Int: computing "remaining = end − now" fresh each tick is
    // what makes this correct across backgrounding. A stored countdown would just freeze in the
    // background and read stale (in fact wrong) the moment the app returns to the foreground.
    @Published var restEndDate: Date?
    // Feature request — "when rest ends... go into negative timing." Deliberately not clamped to
    // 0 anymore: the caller (Train's rest card) is what decides how to display a negative value
    // as overtime, and when to fire the one-time haptic as it crosses zero.
    var restSecondsRemaining: Int {
        guard let restEndDate else { return 0 }
        return Int(restEndDate.timeIntervalSinceNow.rounded())
    }
    // Feature request — "allow users to edit rest timer." UserDefaults-backed (a local display
    // preference, not per-user activity data — same tier as forceDarkMode/remindersEnabled — so
    // it doesn't need a CloudKit round-trip or to survive a reinstall).
    @Published var restDurationSeconds: Int = UserDefaults.standard.object(forKey: "restDurationSeconds") as? Int ?? 105 {
        didSet { UserDefaults.standard.set(restDurationSeconds, forKey: "restDurationSeconds") }
    }
    // Feature request — set right after Finish Workout so WorkoutCompleteView/SessionReviewView
    // have something to show; cleared once the user starts a different day's session (selectDay),
    // since at that point there's nothing "just finished" left to review.
    @Published var lastCompletedSession: WorkoutSession?

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

    init(profile: UserProfile, program: ProgramTemplate, savedPrograms: [ProgramTemplate] = [], startingDayIndex: Int = 0, programStartDate: Date = Date()) {
        self.profile = profile
        self.program = program
        self.savedPrograms = savedPrograms.contains(where: { $0.id == program.id }) ? savedPrograms : savedPrograms + [program]
        self.currentProgramDayIndex = startingDayIndex
        self.programStartDate = programStartDate
        self.bodyweightLogLb = [(Date(), profile.weightKg / 0.45359237)]
        let week = Self.week(fromStartDate: programStartDate)
        self.todaysExercises = Self.buildExerciseSlots(for: program, week: week, dayIndex: startingDayIndex)
        refreshLastPerformance()
    }

    // FRG-206 — 1-indexed; week 1 is the week the program was started in, not the epoch. A static
    // helper (not just a computed property) because `init` needs this before `self` is fully set.
    private static func week(fromStartDate startDate: Date) -> Int {
        let elapsedDays = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return max(1, elapsedDays / 7 + 1)
    }
    var currentProgramWeek: Int { Self.week(fromStartDate: programStartDate) }

    var isDeloadWeek: Bool {
        guard let interval = program.deloadEveryNWeeks, interval > 0 else { return false }
        return currentProgramWeek % interval == 0
    }

    // FRG-104/Feature request — the whole point of a "program": turns its day-by-day exercise
    // list into the actual ExerciseSlots Train/Today read, resolved against whichever week's
    // content applies (default, or a per-week override — see ProgramTemplate.days(forWeek:)).
    // `exercise.name` matching against the exercise it was authored against (curated templates)
    // or picked from the library (custom programs) means this can't silently drop an exercise —
    // ExerciseLibrary.search always has an exact match for names that came from the library itself.
    private static func buildExerciseSlots(for program: ProgramTemplate, week: Int, dayIndex: Int) -> [ExerciseSlot] {
        let days = program.days(forWeek: week)
        guard !days.isEmpty else { return [] }
        let day = days[dayIndex % days.count]
        return day.exercises.compactMap { programExercise -> ExerciseSlot? in
            guard let exercise = resolveExercise(named: programExercise.exerciseName) else { return nil }
            return ExerciseSlot(
                exercise: exercise, targetSets: programExercise.targetSets, targetReps: programExercise.targetReps,
                targetWeightKg: programExercise.targetWeightKg, lastPerformance: nil,
                sets: (0..<programExercise.targetSets).map { _ in LoggedSet(weightKg: programExercise.targetWeightKg, reps: programExercise.targetReps) }
            )
        }
    }

    // Feature request — a custom exercise (added via ExercisePickerSheet, stored in
    // CustomExerciseStore) won't be in the bundled ExerciseLibrary, so program rebuilds need to
    // check both places by name or a swapped-in custom exercise would silently vanish from the
    // day next time todaysExercises gets rebuilt (init, Finish Workout, program edit).
    private static func resolveExercise(named name: String) -> Exercise? {
        ExerciseLibrary.search(name).first(where: { $0.name == name }) ?? CustomExerciseStore.shared.exercise(named: name)
    }

    var currentProgramDayName: String {
        let days = program.days(forWeek: currentProgramWeek)
        guard !days.isEmpty else { return program.name }
        return days[currentProgramDayIndex % days.count].name
    }

    // Feature request — durable program editing (timeframe, per-week content, copy-to-future-
    // weeks), distinct from Feature 2's session-only Train edits. Rebuilds today's exercise list
    // from the updated program immediately, since an in-progress session's plan could have just
    // changed under it — editing your program is a deliberate, infrequent action, not something
    // done mid-set, so resetting today's slate here is an acceptable tradeoff for staying correct.
    func updateProgram(_ newProgram: ProgramTemplate) {
        program = newProgram
        replaceInSavedPrograms(newProgram)
        todaysExercises = Self.buildExerciseSlots(for: newProgram, week: currentProgramWeek, dayIndex: currentProgramDayIndex)
        refreshLastPerformance()
        persistProfile()
    }

    // Feature request — "select which workout program they want to do, especially if they have
    // multiple." Switches to a different program already in the library, or activates a
    // brand-new one just built in ProgramSelectionView. Distinct from `updateProgram`: this is
    // "start this program" (resets to week 1, day 0), not an in-place edit of progress already
    // made on the program currently active.
    func activateProgram(_ selected: ProgramTemplate) {
        replaceInSavedPrograms(selected)
        program = selected
        currentProgramDayIndex = 0
        programStartDate = Date()
        todaysExercises = Self.buildExerciseSlots(for: selected, week: 1, dayIndex: 0)
        refreshLastPerformance()
        lastCompletedSession = nil
        persistProfile()
    }

    // Feature request — DaySelectionView's explicit "do this day" choice, distinct from Finish
    // Workout's automatic rotation to the next day in sequence.
    func selectDay(_ index: Int) {
        currentProgramDayIndex = index
        todaysExercises = Self.buildExerciseSlots(for: program, week: currentProgramWeek, dayIndex: index)
        refreshLastPerformance()
        lastCompletedSession = nil
        persistProfile()
    }

    private func replaceInSavedPrograms(_ updated: ProgramTemplate) {
        if let idx = savedPrograms.firstIndex(where: { $0.id == updated.id }) {
            savedPrograms[idx] = updated
        } else {
            savedPrograms.append(updated)
        }
    }

    private func persistProfile() {
        Task {
            await SyncQueue.shared.enqueue(.profile(
                profile: profile, program: program, savedPrograms: savedPrograms,
                dayIndex: currentProgramDayIndex, programStartDate: programStartDate
            ))
        }
    }

    var currentLoadScore: Double {
        let today = WorkoutSession(date: Date(), sets: todaysExercises.flatMap { slot in
            slot.sets.filter(\.done).map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe, exerciseName: slot.exercise.name) }
        })
        let raw = LoadScoreCalculator.loadScore(today: today, trailingSessions: trailingSessions)
        // FRG-206 — a scheduled deload week forces the score down regardless of trailing volume,
        // same intent as the missed-session case (near-zero volume naturally does this already)
        // but for a week that's *planned* to be lighter, not accidentally skipped.
        return isDeloadWeek ? min(raw, 0.6) : raw
    }

    // FRG-305 — dampens today's Load Score if last night's sleep (from FRG-304's HealthKit read)
    // was poor; never adds calories on its own, only pulls back an already-elevated day.
    private var sleepAdjustedLoadScore: SleepModifier.Result {
        SleepModifier.dampen(loadScore: currentLoadScore, sleepHours: lastNightSleepHours)
    }
    var sleepRecoveryFlagged: Bool { sleepAdjustedLoadScore.recoveryFlagged }

    var nutritionTarget: NutritionTarget {
        let recalibration = WeeklyRecalibrationEngine.recalibratedBaselineAdjustment(profile: profile, weighIns: bodyweightLogLb)
        return NutritionTargetEngine.calculate(profile: profile, loadScore: sleepAdjustedLoadScore.adjustedLoadScore, weeklyRecalibrationKcal: recalibration)
    }

    var hasTrainingHistory: Bool { !trailingSessions.isEmpty }

    // FRG-221 — real per-exercise records from training history, replacing what was previously a
    // hardcoded "Back Squat: 225×5" placeholder in the Progress tab. Heaviest set wins; ties break
    // toward more reps at that weight.
    func personalRecords() -> [(exercise: String, weightKg: Double, reps: Int)] {
        var best: [String: SetLog] = [:]
        for session in trailingSessions {
            for set in session.sets where !set.exerciseName.isEmpty {
                if let current = best[set.exerciseName] {
                    if set.weightKg > current.weightKg || (set.weightKg == current.weightKg && set.reps > current.reps) {
                        best[set.exerciseName] = set
                    }
                } else {
                    best[set.exerciseName] = set
                }
            }
        }
        return best.map { (exercise: $0.key, weightKg: $0.value.weightKg, reps: $0.value.reps) }
            .sorted { $0.weightKg > $1.weightKg }
    }

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

        Task { await SyncQueue.shared.enqueue(.foodEntry(entry: entry, meal: meal)) }
    }

    // FRG-130/131 — appends a new weigh-in; there was previously no UI path that ever grew
    // `bodyweightLogLb` past its single onboarding seed value.
    func logWeight(_ weightLb: Double) {
        let entry = (date: Date(), weightLb: weightLb)
        bodyweightLogLb.append(entry)
        Task { await SyncQueue.shared.enqueue(.bodyweightEntry(date: entry.date, weightLb: entry.weightLb)) }
    }

    // FRG-130/131 — archives today's completed sets into training history and resets the slate
    // for next time. There was previously no path that ever appended to `trailingSessions`, so
    // Load Score never actually changed session to session for a real user.
    func finishWorkout() {
        let completedSets = todaysExercises.flatMap { slot in
            slot.sets.filter(\.done).map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe, exerciseName: slot.exercise.name) }
        }
        guard !completedSets.isEmpty else { return }

        let session = WorkoutSession(date: Date(), sets: completedSets)
        trailingSessions.append(session)
        // Feature request — congratulatory screen + review, reads this.
        lastCompletedSession = session
        workoutsCompletedThisWeek += 1

        // FRG-104 — advance to the next day in the current week's rotation and rebuild the
        // exercise list from it, rather than just resetting today's `done` flags in place. This
        // is also what DaySelectionView highlights as the "suggested" day afterward.
        let daysThisWeek = program.days(forWeek: currentProgramWeek)
        currentProgramDayIndex = daysThisWeek.isEmpty ? 0 : (currentProgramDayIndex + 1) % daysThisWeek.count
        todaysExercises = Self.buildExerciseSlots(for: program, week: currentProgramWeek, dayIndex: currentProgramDayIndex)
        refreshLastPerformance()

        Task { await SyncQueue.shared.enqueue(.workoutSession(session)) }
        persistProfile()
    }

    // FRG-112/113 — the most recent logged set for a given exercise, searched newest-session
    // first; the heaviest set within that session stands in for "what I actually lifted," since
    // set ordering within a session isn't necessarily heaviest-last.
    private func mostRecentSet(for exerciseName: String) -> SetLog? {
        for session in trailingSessions.sorted(by: { $0.date > $1.date }) {
            let matches = session.sets.filter { $0.exerciseName == exerciseName }
            if let top = matches.max(by: { $0.weightKg < $1.weightKg }) { return top }
        }
        return nil
    }

    // FRG-112 — populates ExerciseSlot.lastPerformance from training history; the field existed
    // before this but nothing ever set it, so it always read nil.
    func refreshLastPerformance() {
        for i in todaysExercises.indices {
            guard let last = mostRecentSet(for: todaysExercises[i].exercise.name) else { continue }
            let rpeText = last.rpe.map { " @ RPE \(Int($0))" } ?? ""
            todaysExercises[i].lastPerformance = "\(WeightUnit.roundedLb(fromKg: last.weightKg)) lb × \(last.reps)\(rpeText)"
        }
    }

    // FRG-113 — nil when there's no history for this exercise yet (nothing to base a suggestion
    // on); the caller decides how to present that (e.g. no suggestion card at all).
    func suggestion(for slot: ExerciseSlot) -> ProgressiveOverloadEngine.Suggestion? {
        guard let last = mostRecentSet(for: slot.exercise.name) else { return nil }
        return ProgressiveOverloadEngine.suggestNextSet(lastWeightKg: last.weightKg, lastReps: last.reps, lastRPE: last.rpe, targetReps: slot.targetReps)
    }

    // Applies a suggestion to every not-yet-done set for this exercise — accepting the suggestion
    // is meant to set up the whole remaining working sets at the new load, not just one.
    func applySuggestion(_ suggestion: ProgressiveOverloadEngine.Suggestion, exerciseID: ExerciseSlot.ID) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        for setIdx in todaysExercises[exIdx].sets.indices where !todaysExercises[exIdx].sets[setIdx].done {
            todaysExercises[exIdx].sets[setIdx].weightKg = suggestion.weightKg
            todaysExercises[exIdx].sets[setIdx].reps = suggestion.reps
        }
    }

    // Feature request — "allow them to change it for future weeks if needed." Promotes today's
    // (possibly session-edited) exercise list into the program itself, replacing just today's day
    // slot for the current week and every week after it — past weeks are left alone since they
    // already happened. Reuses `updateProgram` so this goes through the same persistence path and
    // `todaysExercises` rebuild as any other durable program edit.
    func applyTodaysChangesToFutureWeeks() {
        let newDay = ProgramDay(
            name: currentProgramDayName,
            exercises: todaysExercises.map {
                ProgramExercise(exerciseName: $0.exercise.name, targetSets: $0.targetSets, targetReps: $0.targetReps, targetWeightKg: $0.targetWeightKg)
            }
        )
        var newProgram = program
        let startWeek = min(currentProgramWeek, newProgram.weekCount)
        for week in startWeek...newProgram.weekCount {
            var days = newProgram.days(forWeek: week)
            guard currentProgramDayIndex < days.count else { continue }
            days[currentProgramDayIndex] = newDay
            if week == 1 {
                newProgram.defaultDays = days
            } else {
                newProgram.weekOverrides[week] = days
            }
        }
        updateProgram(newProgram)
    }

    // Feature request — session-only editing of today's workout: swap/add/remove exercises,
    // remove sets, edit weight/reps directly. Deliberately doesn't touch `program` at all — this
    // is a one-off substitution ("gym doesn't have this machine today"), not a change to what the
    // program calls for on this day going forward. Durable program editing is a separate,
    // explicit action (program editor), not a side effect of adjusting today's session.

    func removeSet(exerciseID: ExerciseSlot.ID, setID: LoggedSet.ID) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }),
              todaysExercises[exIdx].sets.count > 1 else { return } // never drop to zero sets — remove the exercise instead
        todaysExercises[exIdx].sets.removeAll { $0.id == setID }
    }

    func updateSet(exerciseID: ExerciseSlot.ID, setID: LoggedSet.ID, weightKg: Double, reps: Int) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }),
              let setIdx = todaysExercises[exIdx].sets.firstIndex(where: { $0.id == setID }) else { return }
        todaysExercises[exIdx].sets[setIdx].weightKg = weightKg
        todaysExercises[exIdx].sets[setIdx].reps = reps
    }

    func removeExercise(exerciseID: ExerciseSlot.ID) {
        todaysExercises.removeAll { $0.id == exerciseID }
    }

    func addExercise(_ exercise: Exercise, targetSets: Int = 3, targetReps: Int = 8) {
        let seedWeight = mostRecentSet(for: exercise.name)?.weightKg ?? WeightUnit.kg(fromLb: 45)
        let slot = ExerciseSlot(exercise: exercise, targetSets: targetSets, targetReps: targetReps, targetWeightKg: seedWeight,
                                 lastPerformance: nil, sets: (0..<targetSets).map { _ in LoggedSet(weightKg: seedWeight, reps: targetReps) })
        todaysExercises.append(slot)
        refreshLastPerformance()
    }

    // Keeps target sets/reps (the program's intent for this slot), but re-seeds weight from the
    // new exercise's own history if any exists — carrying over the old exercise's weight onto an
    // unrelated lift wouldn't mean anything.
    func swapExercise(exerciseID: ExerciseSlot.ID, with newExercise: Exercise) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let targetSets = todaysExercises[exIdx].targetSets
        let targetReps = todaysExercises[exIdx].targetReps
        let seedWeight = mostRecentSet(for: newExercise.name)?.weightKg ?? todaysExercises[exIdx].targetWeightKg
        todaysExercises[exIdx] = ExerciseSlot(
            exercise: newExercise, targetSets: targetSets, targetReps: targetReps, targetWeightKg: seedWeight,
            lastPerformance: nil, sets: (0..<targetSets).map { _ in LoggedSet(weightKg: seedWeight, reps: targetReps) }
        )
        refreshLastPerformance()
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
        refreshLastPerformance()
    }

    // FRG-306 — re-evaluates tonight's reminders against current state; call on toggle-enable and
    // on every app backgrounding so a reminder already satisfied earlier today never re-fires.
    func refreshReminders() {
        let workoutDone = todaysExercises.contains { $0.sets.contains { $0.done } }
        ReminderManager.shared.scheduleEveningReminders(workoutDone: workoutDone, mealsLoggedToday: !allFoodEntriesToday().isEmpty)
    }

    func toggleSet(exerciseID: ExerciseSlot.ID, setID: LoggedSet.ID) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }),
              let setIdx = todaysExercises[exIdx].sets.firstIndex(where: { $0.id == setID }) else { return }
        todaysExercises[exIdx].sets[setIdx].done.toggle()
        if todaysExercises[exIdx].sets[setIdx].done { restEndDate = Date().addingTimeInterval(TimeInterval(restDurationSeconds)) }
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
        todaysExercises[exIdx].sets.append(LoggedSet(weightKg: last?.weightKg ?? WeightUnit.kg(fromLb: 45), reps: last?.reps ?? 8))
    }

    // FRG-222 — replaces a hardcoded "5/7 days" placeholder. Reconstructs each of the last 7
    // days' Load Score from sessions strictly before that day (so it reflects what the target
    // actually would have been that day, not today's), then compares that day's logged nutrition
    // total against it. Days with nothing logged are skipped — no data isn't the same as a miss.
    // Approximates with today's profile/weekly-recalibration rather than a historical snapshot,
    // since past profile states aren't persisted — a reasonable simplification for a weekly view.
    func targetHitDaysThisWeek() async -> Int {
        let calendar = Calendar.current
        var hitCount = 0
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: day)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? day

            guard let dayFood = try? await CloudKitStore.shared.fetchFoodEntries(from: startOfDay, to: endOfDay) else { continue }
            let kcalConsumed = dayFood.values.flatMap { $0 }.reduce(0) { $0 + $1.kcal }
            guard kcalConsumed > 0 else { continue }

            let priorSessions = trailingSessions.filter { $0.date < startOfDay }
            let daySession = trailingSessions.first { calendar.isDate($0.date, inSameDayAs: day) }
            let loadScore = LoadScoreCalculator.loadScore(today: daySession, trailingSessions: priorSessions, asOf: startOfDay)
            let target = NutritionTargetEngine.calculate(profile: profile, loadScore: loadScore)

            if abs(Double(kcalConsumed) - target.calories) <= 0.1 * target.calories { hitCount += 1 }
        }
        return hitCount
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
