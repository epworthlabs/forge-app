import Foundation
import CloudKit
import ForgeCore

struct LoggedSet: Identifiable, Equatable, Codable {
    let id = UUID()
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var done: Bool = false
}

struct ExerciseSlot: Identifiable, Equatable, Codable {
    let id = UUID()
    var exercise: Exercise
    var targetSets: Int
    var targetReps: Int
    var targetWeightKg: Double
    var lastPerformance: String?
    var sets: [LoggedSet]
}

struct FoodEntry: Identifiable, Equatable, Codable {
    // `var`, not `let` — an immutable property with a default is *excluded* from synthesized
    // Codable, so a `let id` silently minted a fresh UUID on every decode. Now that entries
    // round-trip through JSON (per-day CloudKit blobs + the local history mirror), the id must
    // survive that trip or merge-by-id dedup would double every entry.
    var id = UUID()
    var date: Date = Date()
    var name: String
    var kcal: Int
    var proteinG: Int
    var carbG: Int
    var fatG: Int
    // Feature request — "give them the ability to edit their serving quantity whether it be in g,
    // oz, or # of servings... macros and calories should update automatically." `quantity`/`unit`/
    // `referenceGrams` reproduce the same multiplier `PortionConfirmSheet` used when this was
    // first logged; `base*` are the food's macros at multiplier 1. Editing the serving size can
    // then rescale kcal/proteinG/carbG/fatG the same way logging did, instead of the user typing
    // raw macro numbers. All defaulted so entries logged before this existed still decode fine —
    // see `effectiveBase*` below for how those fall back gracefully.
    var quantity: Double = 1
    var unit: PortionUnit = .servings
    var referenceGrams: Double? = nil
    var baseKcal: Double? = nil
    var baseProteinG: Double? = nil
    var baseCarbG: Double? = nil
    var baseFatG: Double? = nil
}

extension FoodEntry {
    // A pre-existing entry with no recorded base macros behaves as "1 serving = today's stored
    // macros" — still rescalable by serving count (quantity defaults to 1, unit to .servings),
    // just without a gram reference to offer g/oz editing against.
    var effectiveBaseKcal: Double { baseKcal ?? Double(kcal) }
    var effectiveBaseProteinG: Double { baseProteinG ?? Double(proteinG) }
    var effectiveBaseCarbG: Double { baseCarbG ?? Double(carbG) }
    var effectiveBaseFatG: Double { baseFatG ?? Double(fatG) }
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
    // Feature request — "allow users to traverse through multiple weeks." Which week
    // `todaysExercises` currently reflects — normally the real, date-derived `currentProgramWeek`,
    // but can differ if the user browses to and selects a day from a different week (e.g.
    // catching up on a week they skipped). Distinct from `currentProgramWeek` on purpose: deload
    // scheduling stays tied to real calendar time regardless of which week you're actively
    // training right now.
    @Published private(set) var activeWeek: Int

    // Feature request — "make sure the app knows when we've moved on to the next week and day...
    // just make sure everything in the app updates when a new day and week begins." Nothing
    // previously noticed the wall-clock day changing while the app stayed running (backgrounded
    // and resumed, not fully relaunched) — `mealEntries`/`activeWeek`/`todaysExercises` only ever
    // got recomputed by explicit user actions. Tracked here so `refreshForNewDayIfNeeded()` (called
    // from `MainTabView`'s scenePhase-active hook) has something to compare "now" against.
    private var lastKnownDate = Date()

    // Bug fix — "the workouts/weight/recipes I logged are gone after a day rolls over or I
    // reinstall." Previously invisible: nothing checked whether iCloud was even available before
    // trying to sync, so a device with no signed-in account (or a restricted/degraded one) just
    // silently lost every write with zero indication why. Checked once at launch (see
    // `loadHistoryFromCloudKit`) and surfaced as a warning in You — see `YouView`.
    @Published private(set) var cloudKitAccountStatus: CKAccountStatus = .couldNotDetermine

    @Published var trailingSessions: [WorkoutSession] = []
    // Bug fix — persisted on every change so in-progress (checked-off but not yet Finished) work
    // survives a cold relaunch and an overnight day rollover instead of silently vanishing — see
    // `WorkoutDraftStore` and `resumeOrArchiveDraftIfNeeded()`.
    @Published var todaysExercises: [ExerciseSlot] {
        didSet {
            WorkoutDraftStore.save(WorkoutDraft(
                date: Date(), programDayIndex: currentProgramDayIndex, programWeek: activeWeek,
                exercises: todaysExercises, startedAt: workoutStartedAt
            ))
        }
    }
    // Feature request — "the whole workout should be timed so upon completion, users know how
    // long their workout session was." Set once, on the first set checked off in a fresh session
    // (see `toggleSet`); reset to nil whenever a new session's slate is built (`selectDay`,
    // `activateProgram`, and after `archiveCompletedSession` archives the current one). Carried in
    // `WorkoutDraft` so a relaunch mid-workout doesn't restart the clock.
    @Published var workoutStartedAt: Date?
    // FRG-111 — a Date, not a countdown Int: computing "remaining = end − now" fresh each tick is
    // what makes this correct across backgrounding. A stored countdown would just freeze in the
    // background and read stale (in fact wrong) the moment the app returns to the foreground.
    //
    // Feature request — "notifications for when the rest timer hits 0... and a second notification
    // when user goes -1 min." A `didSet` here (rather than a call at each of the two places that
    // set this — `toggleSet` and the Reset button in `RestTimerCard`) means neither call site nor
    // any future one can forget to (re)schedule the notifications when the rest period restarts.
    @Published var restEndDate: Date? {
        didSet {
            if let restEndDate {
                ReminderManager.shared.scheduleRestTimerNotifications(endDate: restEndDate)
                // Feature request — "rest timer as an app notification... shows the timer on the
                // lock screen." Same trigger point as the one-shot notification above, so neither
                // can be added/changed without the other following along.
                RestTimerActivityManager.shared.start(endDate: restEndDate, exerciseName: restExerciseName)
            } else {
                ReminderManager.shared.cancelRestTimerNotifications()
                RestTimerActivityManager.shared.end()
            }
        }
    }
    // Feature request — Live Activity needs a label ("Bench Press", not just a bare countdown);
    // `restEndDate`'s own didSet has no way to know which exercise just triggered it, so `toggleSet`
    // sets this immediately beforehand. Not scoped tighter (e.g. passed as a didSet parameter)
    // because `restEndDate` also gets reassigned directly from the Reset button in
    // `RestTimerCard`, which has no exercise context of its own — reusing whatever name is already
    // here is correct for that case, since Reset never changes which exercise is resting.
    private var restExerciseName: String = "Rest"
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

    // Feature request — "pull the workouts completed metric based on the active workout program
    // user is participating in. If it's 3x a week and completed 1 of 3, that metric is 1/3."
    // These were hardcoded placeholders (4 and 5, permanently) until now — `workoutsCompletedThisWeek`
    // never actually reset week to week, it just incremented forever.
    var workoutsPlannedThisWeek: Int { program.daysPerWeek }
    var workoutsCompletedThisWeek: Int {
        guard let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return trailingSessions.filter { weekInterval.contains($0.date) }.count
    }

    @Published var sheetPresented = false

    // FRG-304 — nil until Health sync is enabled and a fetch completes.
    @Published var stepsToday: Int?
    @Published var lastNightSleepHours: Double?

    // FRG-302 — recent/frequent foods, capped and deduped by name+brand, most-recent first.
    @Published private(set) var recentFoods: [FoodSearchResult] = []

    // Feature request — "let users see a list of favourite foods whenever they go to add to their
    // meals... users should also be able to edit that favourites list." Unlike `recentFoods` (an
    // implicit MRU list, session-scoped and rebuilt from logging), favorites are an explicit user
    // choice — expected to survive relaunch, so this is UserDefaults-backed (same local-only
    // pattern as `restDurationSeconds` above) rather than living only in memory.
    @Published private(set) var favoriteFoods: [FoodSearchResult] = {
        guard let data = UserDefaults.standard.data(forKey: "favoriteFoods"),
              let decoded = try? JSONDecoder().decode([FoodSearchResult].self, from: data) else { return [] }
        return decoded
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(favoriteFoods) {
                UserDefaults.standard.set(data, forKey: "favoriteFoods")
            }
        }
    }

    func isFavoriteFood(_ food: FoodSearchResult) -> Bool {
        favoriteFoods.contains { $0.name == food.name && $0.brand == food.brand }
    }

    func toggleFavoriteFood(_ food: FoodSearchResult) {
        if isFavoriteFood(food) {
            favoriteFoods.removeAll { $0.name == food.name && $0.brand == food.brand }
        } else {
            favoriteFoods.insert(food, at: 0)
        }
    }

    let foodSearchService = FoodSearchService(credentials: Secrets.foodDatabaseCredentials, countryFilter: Secrets.foodDatabaseCountryFilter)

    init(profile: UserProfile, program: ProgramTemplate, savedPrograms: [ProgramTemplate] = [], startingDayIndex: Int = 0, programStartDate: Date = Date()) {
        self.profile = profile
        self.program = program
        self.savedPrograms = savedPrograms.contains(where: { $0.id == program.id }) ? savedPrograms : savedPrograms + [program]
        self.currentProgramDayIndex = startingDayIndex
        self.programStartDate = programStartDate
        self.bodyweightLogLb = [(Date(), profile.weightKg / 0.45359237)]
        let week = Self.week(fromStartDate: programStartDate)
        self.activeWeek = week
        self.todaysExercises = Self.buildExerciseSlots(for: program, week: week, dayIndex: startingDayIndex)

        // Root-cause fix (FRG-383) — seed history from the device-local mirror synchronously,
        // before any CloudKit round-trip is even attempted. A cold launch (which is what a "day
        // rollover" is in practice — the app relaunches the next morning) previously started with
        // empty history and depended entirely on a CloudKit fetch that was silently failing; now
        // yesterday's sessions/weigh-ins are on screen from the first frame, and CloudKit merges
        // on top later. Meals only apply if they belong to today — a new day starts empty.
        if let cached = LocalHistoryStore.load() {
            if !cached.sessions.isEmpty { trailingSessions = cached.sessions }
            if !cached.weighIns.isEmpty { bodyweightLogLb = cached.weighIns.map { ($0.date, $0.weightLb) } }
            if cached.mealsDayKey == DayKey.today { mealEntries = cached.meals }
        }
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
            // Feature request — "when weights are first listed by default... always defaulted to
            // increments of 5." Safety net beyond just re-authoring the curated templates in round
            // numbers: any program (custom-built, or a future template) gets clean defaults here
            // regardless of what the stored value actually is.
            let weight = WeightUnit.roundedToNearestFiveLb(fromKg: programExercise.targetWeightKg)
            return ExerciseSlot(
                exercise: exercise, targetSets: programExercise.targetSets, targetReps: programExercise.targetReps,
                targetWeightKg: weight, lastPerformance: nil,
                sets: (0..<programExercise.targetSets).map { _ in LoggedSet(weightKg: weight, reps: programExercise.targetReps) }
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
        activeWeek = currentProgramWeek
        todaysExercises = Self.buildExerciseSlots(for: newProgram, week: activeWeek, dayIndex: currentProgramDayIndex)
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
        activeWeek = 1
        // A brand-new session slate — the previous one's clock (if any) doesn't carry over.
        workoutStartedAt = nil
        todaysExercises = Self.buildExerciseSlots(for: selected, week: 1, dayIndex: 0)
        refreshLastPerformance()
        lastCompletedSession = nil
        persistProfile()
    }

    // Feature request — "there needs to be a way to delete a workout program... hold and delete,
    // much like iOS." Always leaves at least one program (nothing to fall back to otherwise); if
    // the deleted program was the active one, activates whatever's left instead of leaving `program`
    // pointing at a template no longer in `savedPrograms`.
    func removeProgram(_ target: ProgramTemplate) {
        guard savedPrograms.count > 1 else { return }
        let wasActive = target.id == program.id
        savedPrograms.removeAll { $0.id == target.id }
        if wasActive, let next = savedPrograms.first {
            activateProgram(next)
        } else {
            persistProfile()
        }
    }

    // Feature request — DaySelectionView's explicit "do this day" choice, distinct from Finish
    // Workout's automatic rotation to the next day in sequence. `week` defaults to the real
    // current week, but DaySelectionView can pass a different one when the user has browsed to
    // and picked a day from a week they're catching up on ("allow users to traverse through
    // multiple weeks").
    func selectDay(_ index: Int, week: Int? = nil) {
        currentProgramDayIndex = index
        activeWeek = week ?? currentProgramWeek
        // A brand-new session slate — the previous one's clock (if any) doesn't carry over.
        workoutStartedAt = nil
        todaysExercises = Self.buildExerciseSlots(for: program, week: activeWeek, dayIndex: index)
        refreshLastPerformance()
        lastCompletedSession = nil
        persistProfile()
    }

    /// Feature request — "if the user completed one of the workouts for the week in a specific
    /// training program, denote that specific workout was completed for the week." Which day
    /// indices (within `week`) already have a logged session, so DayTile can show a completed
    /// badge and the suggestion below can skip past them.
    ///
    /// Bug fix — "when I mark off the first workout in a program, it marks off the first workout
    /// in other programs too." Also matching on `programID` now, not just week/day — two different
    /// programs' Week 1/Day 0 are otherwise indistinguishable. A `nil` programID (a session logged
    /// before this field existed) is treated as belonging to whichever program is active right now
    /// rather than excluded outright, so existing completion history isn't silently lost.
    func completedDayIndices(forWeek week: Int) -> Set<Int> {
        Set(trailingSessions.compactMap {
            guard $0.programWeek == week, $0.programID == nil || $0.programID == program.id else { return nil }
            return $0.programDayIndex
        })
    }

    /// Bug fix — "the suggested exercise to go to the next week if all the exercises in the week
    /// tab is completed. It should never suggest a completed workout." + "when the user taps into
    /// a workout program, it should display the week that the suggested workout is at, not week
    /// 1." `currentProgramWeek` is purely calendar-based (elapsed days ÷ 7) — someone training
    /// more often than the program's own cadence can fully finish "this week" well before the
    /// calendar week is over. The old day-only version of this only ever looked *within* the given
    /// week and fell back to day 0 — already completed — once everything in it was done. This
    /// instead walks forward from `currentProgramWeek` until it finds a week with something left
    /// to do, so both the suggestion itself and whichever week `DaySelectionView` opens to reflect
    /// actual progress, not just the calendar.
    func suggestedSession() -> (week: Int, dayIndex: Int) {
        var week = currentProgramWeek
        while week <= program.weekCount {
            let days = program.days(forWeek: week)
            if !days.isEmpty {
                let done = completedDayIndices(forWeek: week)
                if let dayIndex = (0..<days.count).first(where: { !done.contains($0) }) {
                    return (week, dayIndex)
                }
            }
            week += 1
        }
        // Every remaining week through the program's own timeframe is already fully completed —
        // nothing meaningful left to suggest; land on day 0 of the last week rather than pointing
        // past the program's timeframe entirely.
        return (max(1, program.weekCount), 0)
    }

    // Feature request — "there needs to be a way to delete... workouts within the week... hold
    // and delete." Scoped to the viewed week only (not every week the program has) — creates or
    // overwrites that week's override with the day removed, leaving other weeks untouched. Always
    // leaves at least one day in the week.
    func removeDay(atIndex index: Int, forWeek week: Int) {
        var days = program.days(forWeek: week)
        guard days.indices.contains(index), days.count > 1 else { return }
        days.remove(at: index)
        var updated = program
        updated.weekOverrides[week] = days
        updateProgram(updated)
    }

    // Feature request — "this figure should not change unless these settings are changed in the
    // app." The one and only place, besides onboarding, that's allowed to move the target-driven
    // calorie baseline: an explicit edit here, not a side effect of logging a new weigh-in or
    // finishing a workout. `targetWeightKg`/`targetWeeks` are re-anchored to `profile.weightKg`
    // as it stands right now — same "fixed until you touch it again" contract as onboarding's.
    func updateGoalAndTarget(goal: Goal, targetWeightLb: Double?, targetWeeks: Int?) {
        let hasWeightTarget = goal == .cut || goal == .bulk
        profile.goal = goal
        profile.targetWeightKg = hasWeightTarget ? targetWeightLb.map { $0 * 0.45359237 } : nil
        profile.targetWeeks = hasWeightTarget ? targetWeeks : nil
        persistProfile()
    }

    // Feature request — "protein intake seems a bit low, I want users to be able to adjust the
    // target macro splits manually if needed." Percentages, nil to go back to the computed
    // default (goal-based protein g/kg + flexible carbs) — see NutritionTargetEngine.calculate.
    func updateMacroSplit(proteinPercent: Double?, carbPercent: Double?, fatPercent: Double?) {
        profile.manualProteinPercent = proteinPercent
        profile.manualCarbPercent = carbPercent
        profile.manualFatPercent = fatPercent
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
    // was poor. Since Load Score no longer swings calories (see NutritionTargetEngine), this only
    // affects carbBand's macro split now, not the calorie total.
    private var sleepAdjustedLoadScore: SleepModifier.Result {
        SleepModifier.dampen(loadScore: currentLoadScore, sleepHours: lastNightSleepHours)
    }

    var nutritionTarget: NutritionTarget {
        let recalibration = WeeklyRecalibrationEngine.recalibratedBaselineAdjustment(profile: profile, weighIns: bodyweightLogLb)
        return NutritionTargetEngine.calculate(profile: profile, loadScore: sleepAdjustedLoadScore.adjustedLoadScore, weeklyRecalibrationKcal: recalibration)
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

    // `quantity`/`unit`/`referenceGrams` are the portion actually chosen in PortionConfirmSheet;
    // `result`'s own kcal/proteinG/carbG/fatG are the food's *base* macros (at multiplier 1), kept
    // so the entry can be rescaled later instead of only ever storing the already-scaled numbers.
    func logFood(_ result: FoodSearchResult, quantity: Double, unit: PortionUnit, referenceGrams: Double?, to meal: Meal) {
        let multiplier = PortionScaling.multiplier(quantity: quantity, unit: unit, referenceGrams: referenceGrams)
        let entry = FoodEntry(
            name: result.name,
            kcal: Int((Double(result.kcal) * multiplier).rounded()),
            proteinG: Int((result.proteinG * multiplier).rounded()),
            carbG: Int((result.carbG * multiplier).rounded()),
            fatG: Int((result.fatG * multiplier).rounded()),
            quantity: quantity, unit: unit, referenceGrams: referenceGrams,
            baseKcal: Double(result.kcal), baseProteinG: result.proteinG, baseCarbG: result.carbG, baseFatG: result.fatG
        )
        mealEntries[meal, default: []].append(entry)

        recentFoods.removeAll { $0.name == result.name && $0.brand == result.brand }
        recentFoods.insert(result, at: 0)
        if recentFoods.count > 10 { recentFoods.removeLast() }

        // FRG-306 — no-op if no meal reminder is pending (reminders off, or already cancelled).
        ReminderManager.shared.cancelMealReminder()

        syncTodayFood()
    }

    // Feature request — "scrap the current editing flow... give them the ability to edit their
    // serving quantity... macros and calories should update automatically." Replaces the old
    // raw-numeric macro editor: recomputes kcal/proteinG/carbG/fatG from the entry's base macros
    // every time, rather than accepting them as separately typed numbers.
    // `referenceGrams` is passed in (not read off the existing entry) because switching to a
    // weight-based unit on an entry that never had one — "I can't change from servings to g or oz
    // when I edit, make it so I can" — establishes that reference for the first time; every other
    // edit just passes the entry's existing value straight back through unchanged.
    func updateFoodEntryPortion(id: FoodEntry.ID, in meal: Meal, name: String, quantity: Double, unit: PortionUnit, referenceGrams: Double?) {
        guard let index = mealEntries[meal]?.firstIndex(where: { $0.id == id }) else { return }
        var updated = mealEntries[meal]![index]
        let multiplier = PortionScaling.multiplier(quantity: quantity, unit: unit, referenceGrams: referenceGrams)
        updated.name = name
        updated.quantity = quantity
        updated.unit = unit
        updated.referenceGrams = referenceGrams
        updated.kcal = Int((updated.effectiveBaseKcal * multiplier).rounded())
        updated.proteinG = Int((updated.effectiveBaseProteinG * multiplier).rounded())
        updated.carbG = Int((updated.effectiveBaseCarbG * multiplier).rounded())
        updated.fatG = Int((updated.effectiveBaseFatG * multiplier).rounded())
        mealEntries[meal]![index] = updated
        syncTodayFood()
    }

    func removeFoodEntry(id: FoodEntry.ID, from meal: Meal) {
        mealEntries[meal]?.removeAll { $0.id == id }
        syncTodayFood()
    }

    // FRG-383 — one path for every today's-diary mutation: mirror to local disk immediately
    // (survives relaunch with no network at all), then push the whole day to CloudKit (a delete
    // is just the next save without the entry — no per-entry delete case anymore).
    private func syncTodayFood() {
        persistLocalHistory()
        let dayKey = DayKey.today
        let snapshot = mealEntries
        Task { await SyncQueue.shared.enqueue(.foodDay(dayKey: dayKey, entries: snapshot)) }
    }

    // FRG-383 — the device-local mirror of everything `loadHistoryFromCloudKit` would otherwise
    // have to re-fetch; written on every history mutation, read back synchronously in `init`.
    private func persistLocalHistory() {
        LocalHistoryStore.save(LocalHistoryStore.Snapshot(
            sessions: trailingSessions,
            weighIns: bodyweightLogLb.map { BodyweightEntry(date: $0.date, weightLb: $0.weightLb) },
            mealsDayKey: DayKey.today,
            meals: mealEntries
        ))
    }

    // FRG-130/131 — appends a new weigh-in; there was previously no UI path that ever grew
    // `bodyweightLogLb` past its single onboarding seed value.
    func logWeight(_ weightLb: Double) {
        bodyweightLogLb.append((date: Date(), weightLb: weightLb))
        persistLocalHistory()
        let snapshot = bodyweightLogLb.map { BodyweightEntry(date: $0.date, weightLb: $0.weightLb) }
        Task { await SyncQueue.shared.enqueue(.bodyweightLog(snapshot)) }
    }

    // Feature request — "users should be able to edit their current weight in the profile section
    // as well as the goal & target section. Make sure this is taken into account when determining
    // target calories along with all the other info." Deliberately distinct from `logWeight` (the
    // frequent "+ Log weight" quick action, which only ever fed the slow, smoothed weekly
    // recalibration so ordinary day-to-day fluctuation doesn't whipsaw the calorie target) — this
    // is an explicit "update my stats" edit, the same category `updateGoalAndTarget` already
    // occupies as the one place besides onboarding allowed to move the baseline directly.
    // `profile.weightKg` feeds `TDEECalculator`/`estimatedFatFreeMassKg` live on every read (both
    // are plain computed reads off `profile`, never cached), so `nutritionTarget` reflects this on
    // its very next access — no extra wiring needed beyond writing the new value and persisting.
    // Also logs a weigh-in so the bodyweight history/chart never disagrees with the profile.
    func updateCurrentWeight(_ weightLb: Double) {
        profile.weightKg = weightLb * 0.45359237
        logWeight(weightLb)
        persistProfile()
    }

    // FRG-130/131 — archives completed sets into training history and rotates to the next
    // suggested day. There was previously no path that ever appended to `trailingSessions`, so
    // Load Score never actually changed session to session for a real user.
    //
    // Bug fix — pulled out of `finishWorkout()` so the exact same archive-and-advance logic can
    // also run automatically when a day boundary is crossed with checked-off-but-never-Finished
    // sets sitting around (see `refreshForNewDayIfNeeded` and `resumeOrArchiveDraftIfNeeded`),
    // instead of just discarding them. Takes `exercises`/`dayIndex`/`week` as parameters rather
    // than reading `todaysExercises`/`currentProgramDayIndex`/`activeWeek` directly because the
    // draft-recovery caller archives a *previous* day's snapshot, not whatever's currently loaded.
    // `startedAt` is the same story — the draft-recovery caller passes the *draft's* recorded
    // start time, not whatever `workoutStartedAt` currently holds.
    @discardableResult
    private func archiveCompletedSession(exercises: [ExerciseSlot], dayIndex: Int, week: Int, startedAt: Date?) -> WorkoutSession? {
        let completedSets = exercises.flatMap { slot in
            slot.sets.filter(\.done).map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe, exerciseName: slot.exercise.name) }
        }
        guard !completedSets.isEmpty else { return nil }
        // A session just got archived — no more sets left to rest between, so any pending
        // "time to start your next set" notification would fire after the fact.
        ReminderManager.shared.cancelRestTimerNotifications()
        RestTimerActivityManager.shared.end()

        // Feature request — "denote that specific workout was completed for the week." Tagged
        // with whichever day/week was actually being trained, not necessarily the real current
        // week (see `selectDay`), so completion tracking is correct even when catching up on a
        // different week. Also tagged with the active program's id — bug fix, "when I mark off
        // the first workout in a program, it marks off the first workout in other programs too."
        // Feature request — "the whole workout should be timed" — `durationSeconds` is nil only
        // for a session with no recorded start (shouldn't happen in practice since `toggleSet`
        // always sets one on the first completed set, but a missing start shouldn't crash or
        // fabricate a number).
        let durationSeconds = startedAt.map { Int(Date().timeIntervalSince($0).rounded()) }
        let session = WorkoutSession(
            date: Date(), sets: completedSets, programDayIndex: dayIndex, programWeek: week,
            programID: program.id, durationSeconds: durationSeconds
        )
        trailingSessions.append(session)
        // Feature request — congratulatory screen + review, reads this.
        lastCompletedSession = session
        workoutStartedAt = nil

        // Feature request — "suggest the next workout depending on the week and what has already
        // been done" — the next not-yet-done day, rather than blindly rotating to "whatever's
        // next in sequence" regardless of what's actually been completed. Bug fix — this used to
        // always land back on `currentProgramWeek` (the real calendar week) even if every day in
        // it was now done, re-suggesting a completed workout; `suggestedSession()` walks forward
        // to the next week with something left instead.
        let next = suggestedSession()
        activeWeek = next.week
        currentProgramDayIndex = next.dayIndex
        todaysExercises = Self.buildExerciseSlots(for: program, week: activeWeek, dayIndex: currentProgramDayIndex)
        refreshLastPerformance()

        // FRG-383 — mirror locally first (relaunch-safe with zero network), then push the whole
        // history; CloudKitStore unions by session id server-side, so this can't clobber
        // anything a fetch hasn't seen yet.
        persistLocalHistory()
        let snapshot = trailingSessions
        Task { await SyncQueue.shared.enqueue(.workoutSessions(snapshot)) }
        return session
    }

    func finishWorkout() {
        guard archiveCompletedSession(exercises: todaysExercises, dayIndex: currentProgramDayIndex, week: activeWeek, startedAt: workoutStartedAt) != nil else { return }
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
    //
    // Feature request — "increase by increments of 5 or 2.5lbs, depending on the exercise."
    // Barbell lifts move in 5lb jumps (a 2.5lb plate per side); everything else (dumbbell,
    // machine, cable, bodyweight-plus-load) gets the finer 2.5lb step, since that equipment
    // typically doesn't offer 5lb jumps in the first place.
    func suggestion(for slot: ExerciseSlot) -> ProgressiveOverloadEngine.Suggestion? {
        guard let last = mostRecentSet(for: slot.exercise.name) else { return nil }
        let incrementLb: Double = slot.exercise.equipment == "barbell" ? 5 : 2.5
        return ProgressiveOverloadEngine.suggestNextSet(
            lastWeightKg: last.weightKg, lastReps: last.reps, lastRPE: last.rpe, targetReps: slot.targetReps,
            roundingIncrementKg: WeightUnit.kg(fromLb: incrementLb)
        )
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

    // Feature request — "if user makes updates to the weights & reps, auto update weights & reps
    // for the sets below it." Cascades only to not-yet-done sets after this one — same reasoning
    // `applySuggestion` already uses: a set already marked done is a historical record of what was
    // actually performed, not a target to silently overwrite. Editing an earlier set (done or not)
    // still cascades forward; only *later*, already-done sets are left alone.
    func updateSet(exerciseID: ExerciseSlot.ID, setID: LoggedSet.ID, weightKg: Double, reps: Int) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }),
              let setIdx = todaysExercises[exIdx].sets.firstIndex(where: { $0.id == setID }) else { return }
        todaysExercises[exIdx].sets[setIdx].weightKg = weightKg
        todaysExercises[exIdx].sets[setIdx].reps = reps
        for laterIdx in (setIdx + 1)..<todaysExercises[exIdx].sets.count where !todaysExercises[exIdx].sets[laterIdx].done {
            todaysExercises[exIdx].sets[laterIdx].weightKg = weightKg
            todaysExercises[exIdx].sets[laterIdx].reps = reps
        }
    }

    func removeExercise(exerciseID: ExerciseSlot.ID) {
        todaysExercises.removeAll { $0.id == exerciseID }
    }

    // Bug fix — "when we move it, I want it more responsive: if I drag the gripped card on top of
    // another card, it should immediately go above it if it's currently below, or below it if
    // it's currently above." The old version always inserted the dragged card immediately
    // *before* the target — correct for dragging upward (the dragged card was below, ends up
    // above, matching the request), but for dragging downward it always stopped one slot short of
    // where the target actually was instead of passing it, which read as sluggish/unresponsive.
    // Direction is inferred from the two cards' positions *before* the move: dragging downward
    // (dragged was above target) inserts *after* the target; dragging upward (dragged was below)
    // inserts *before* it, same as always. No-op if either side of the drag isn't found (e.g. the
    // dragged card was removed mid-gesture) rather than crashing.
    func moveExercise(id: ExerciseSlot.ID, near targetID: ExerciseSlot.ID) {
        guard id != targetID,
              let fromIndex = todaysExercises.firstIndex(where: { $0.id == id }),
              let targetIndexBeforeMove = todaysExercises.firstIndex(where: { $0.id == targetID }) else { return }
        let draggingDown = fromIndex < targetIndexBeforeMove
        let slot = todaysExercises.remove(at: fromIndex)
        guard let targetIndex = todaysExercises.firstIndex(where: { $0.id == targetID }) else {
            todaysExercises.insert(slot, at: min(fromIndex, todaysExercises.count))
            return
        }
        todaysExercises.insert(slot, at: draggingDown ? targetIndex + 1 : targetIndex)
    }

    // Feature request — "let's also add a move to bottom button in the ... menu item and move to
    // top button as well."
    func moveExerciseToTop(exerciseID: ExerciseSlot.ID) {
        guard let index = todaysExercises.firstIndex(where: { $0.id == exerciseID }), index != 0 else { return }
        let slot = todaysExercises.remove(at: index)
        todaysExercises.insert(slot, at: 0)
    }

    func moveExerciseToBottom(exerciseID: ExerciseSlot.ID) {
        guard let index = todaysExercises.firstIndex(where: { $0.id == exerciseID }), index != todaysExercises.count - 1 else { return }
        let slot = todaysExercises.remove(at: index)
        todaysExercises.append(slot)
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
    //
    // Bug fix — this used to replace the array element with a brand-new `ExerciseSlot(...)`
    // value. `ExerciseSlot.id` is a fresh `UUID()` generated at init time, so that silently gave
    // the swapped-in exercise a *different* identity than the one it replaced. `ForEach` in
    // TrainView diffs by that id, so SwiftUI tore down the old ExerciseCard (and its @State) and
    // mounted a brand new one in the same render pass — which is why the "apply to future weeks?"
    // prompt set on the old view's state right before swapping never actually appeared. Mutating
    // the existing slot's fields in place instead preserves `id`, so the same view instance lives
    // on and the prompt (now owned by the parent anyway — see TrainSessionView) works correctly.
    func swapExercise(exerciseID: ExerciseSlot.ID, with newExercise: Exercise) {
        guard let exIdx = todaysExercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let targetSets = todaysExercises[exIdx].targetSets
        let targetReps = todaysExercises[exIdx].targetReps
        let seedWeight = mostRecentSet(for: newExercise.name)?.weightKg ?? todaysExercises[exIdx].targetWeightKg
        todaysExercises[exIdx].exercise = newExercise
        todaysExercises[exIdx].targetWeightKg = seedWeight
        todaysExercises[exIdx].lastPerformance = nil
        todaysExercises[exIdx].sets = (0..<targetSets).map { _ in LoggedSet(weightKg: seedWeight, reps: targetReps) }
        refreshLastPerformance()
    }

    // FRG-130/131 — backfills history for a returning user; called once after construction
    // rather than from `init` so the synchronous init never blocks on a network round-trip.
    // FRG-383 — every fetch merges (union by id/timestamp) with what's already in memory rather
    // than replacing it, so a fetch can never wipe out something logged moments ago that hasn't
    // round-tripped yet; and every failure is logged instead of silently swallowed, which is how
    // the original "everything vanishes" bug stayed invisible for so long.
    func loadHistoryFromCloudKit() async {
        async let sessionsFetch = CloudKitStore.shared.fetchAllWorkoutSessions()
        async let weighInsFetch = CloudKitStore.shared.fetchBodyweightLog()
        async let todaysFoodFetch = CloudKitStore.shared.fetchFoodDay(dayKey: DayKey.today)
        async let accountStatus = CloudKitStore.shared.accountStatus()

        do {
            let fetched = try await sessionsFetch
            let fetchedIDs = Set(fetched.map(\.id))
            trailingSessions = (fetched + trailingSessions.filter { !fetchedIDs.contains($0.id) })
                .sorted { $0.date < $1.date }
        } catch {
            print("[CloudKit] workout history fetch failed: \(error)")
        }
        do {
            let fetched = try await weighInsFetch
            let fetchedStamps = Set(fetched.map(\.date))
            let localOnly = bodyweightLogLb.filter { !fetchedStamps.contains($0.date) }
            bodyweightLogLb = (fetched.map { ($0.date, $0.weightLb) } + localOnly)
                .sorted { $0.date < $1.date }
        } catch {
            print("[CloudKit] bodyweight fetch failed: \(error)")
        }
        do {
            var merged = try await todaysFoodFetch
            for meal in Meal.allCases {
                let fetchedIDs = Set((merged[meal] ?? []).map(\.id))
                merged[meal, default: []] += (mealEntries[meal] ?? []).filter { !fetchedIDs.contains($0.id) }
            }
            mealEntries = merged
        } catch {
            print("[CloudKit] today's food fetch failed: \(error)")
        }
        cloudKitAccountStatus = await accountStatus
        refreshLastPerformance()
        persistLocalHistory()
    }

    // Feature request — "make sure the app knows when we've moved on to the next week and day...
    // my food log in the eat tab and the metrics on the today tab didn't update... even my
    // calendar didn't retain the workout from yesterday." Call whenever the app becomes active
    // (see `MainTabView`'s scenePhase hook) — a no-op unless the wall-clock day has actually
    // changed since the last check, so this doesn't hit CloudKit on every foreground within the
    // same day. Re-fetching history picks up anything that finished syncing while backgrounded
    // (addresses "the calendar didn't retain yesterday's workout"); resetting `mealEntries` to a
    // fresh fetch scoped to the new "today" clears out yesterday's stale entries instead of
    // leaving them showing under a new day; rebuilding `todaysExercises` against the recomputed
    // `activeWeek` picks up a week boundary crossed while away, without changing which day was
    // already selected.
    func refreshForNewDayIfNeeded() async {
        guard !Calendar.current.isDate(lastKnownDate, inSameDayAs: Date()) else { return }
        lastKnownDate = Date()
        // Bug fix — "the workout that's checked off gets unchecked and resets... the calendar
        // isn't marking the days off either." Snapshot whatever's currently checked off *before*
        // the rebuild below discards it — if the day rolled over while the app sat backgrounded
        // mid-session, that's real completed work that was never explicitly Finished, not nothing.
        let staleExercises = todaysExercises
        let staleDayIndex = currentProgramDayIndex
        let staleWeek = activeWeek
        let staleStartedAt = workoutStartedAt
        // New day: yesterday's meals must be cleared *before* the fetch below, since
        // loadHistoryFromCloudKit now merges (unions) into whatever's in memory — without this,
        // yesterday's entries would leak into today's diary.
        mealEntries = [.breakfast: [], .lunch: [], .dinner: [], .snacks: []]
        // Fetch first: archiving appends to `trailingSessions`, and the archived session should
        // land on top of freshly merged history rather than racing the fetch.
        await loadHistoryFromCloudKit()
        if archiveCompletedSession(exercises: staleExercises, dayIndex: staleDayIndex, week: staleWeek, startedAt: staleStartedAt) != nil {
            persistProfile()
        } else {
            activeWeek = currentProgramWeek
            todaysExercises = Self.buildExerciseSlots(for: program, week: activeWeek, dayIndex: currentProgramDayIndex)
            refreshLastPerformance()
        }
    }

    // Bug fix — the cold-launch counterpart to `refreshForNewDayIfNeeded` above: a day boundary
    // crossed while the app wasn't running at all never went through that live-foreground check,
    // so checked-off sets from a session that was never Finished were silently lost on next
    // launch with no record of them anywhere. Call once after `loadHistoryFromCloudKit()` so an
    // archived session lands on top of fresh history rather than racing it (same reasoning as
    // `refreshForNewDayIfNeeded`).
    func resumeOrArchiveDraftIfNeeded() async {
        guard let draft = WorkoutDraftStore.load() else { return }
        // Same slot as what's currently loaded (today, same program day/week) — a same-day
        // relaunch, not a rollover. Restore it so a cold launch mid-workout doesn't wipe progress
        // `init`'s fresh rebuild already discarded in memory.
        let isCurrentSlot = Calendar.current.isDateInToday(draft.date)
            && draft.programDayIndex == currentProgramDayIndex && draft.programWeek == activeWeek
        if isCurrentSlot {
            // Restore the real elapsed-time clock too, before `todaysExercises` below re-persists
            // the draft — otherwise a relaunch mid-workout would silently restart the timer.
            workoutStartedAt = draft.startedAt
            todaysExercises = draft.exercises
            return
        }
        // Anything else — a previous day, or a slot that's no longer current (e.g. a different
        // day/program was selected since) — archive whatever was checked off under it rather than
        // just dropping it. No-op if nothing was actually checked off.
        if archiveCompletedSession(exercises: draft.exercises, dayIndex: draft.programDayIndex, week: draft.programWeek, startedAt: draft.startedAt) != nil {
            persistProfile()
        }
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
        // Feature request — "the whole workout should be timed." Starts the clock on the first set
        // checked off in a fresh session — set *before* the mutation below, so the draft persisted
        // by `todaysExercises`'s didSet captures it on this same write, not the next one.
        if !todaysExercises[exIdx].sets[setIdx].done && workoutStartedAt == nil {
            workoutStartedAt = Date()
        }
        todaysExercises[exIdx].sets[setIdx].done.toggle()
        if todaysExercises[exIdx].sets[setIdx].done {
            restExerciseName = todaysExercises[exIdx].exercise.name
            restEndDate = Date().addingTimeInterval(TimeInterval(restDurationSeconds))
        }
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

    // Feature request — "replace target hit with a metric for nutrition that adds value and
    // insight to how on track they are towards their specified goals." A binary hit/miss count
    // (FRG-222's original "X/7 days") threw away exactly how far off a day was — this reports the
    // actual average, both in raw calories and as a percentage of target, so "close but a bit
    // under" and "way over" read differently instead of both just counting as a miss. Same
    // reconstruction approach as before: each day's Load Score is rebuilt from sessions strictly
    // before that day, and days with nothing logged are skipped (no data isn't the same as 0).
    struct NutritionWeekSummary {
        var daysLogged: Int
        var avgCalories: Int
        var avgTargetCalories: Int
        var avgCaloriePercent: Int
    }

    func nutritionWeekSummary() async -> NutritionWeekSummary {
        let calendar = Calendar.current
        var daysLogged = 0
        var calorieSum = 0
        var targetSum = 0.0
        // Calories are now fixed by activity level + goal + weekly recalibration only (no more
        // per-day Load Score swing), so the target is the same every day — computed once rather
        // than re-deriving a per-day Load Score that no longer changes the result.
        let dailyTargetCalories = NutritionTargetEngine.calculate(profile: profile, loadScore: 1.0).calories
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }

            // Today reads straight from live in-memory state — always ahead of (or equal to) the
            // server; past days come from their per-day CloudKit records (FRG-383).
            let dayFood: [Meal: [FoodEntry]]
            if dayOffset == 0 {
                dayFood = mealEntries
            } else if let fetched = try? await CloudKitStore.shared.fetchFoodDay(dayKey: DayKey.string(for: day)) {
                dayFood = fetched
            } else {
                continue
            }
            let kcalConsumed = dayFood.values.flatMap { $0 }.reduce(0) { $0 + $1.kcal }
            guard kcalConsumed > 0 else { continue }

            daysLogged += 1
            calorieSum += kcalConsumed
            targetSum += dailyTargetCalories
        }
        guard daysLogged > 0 else { return NutritionWeekSummary(daysLogged: 0, avgCalories: 0, avgTargetCalories: 0, avgCaloriePercent: 0) }
        let avgCalories = calorieSum / daysLogged
        let avgTarget = targetSum / Double(daysLogged)
        return NutritionWeekSummary(
            daysLogged: daysLogged,
            avgCalories: avgCalories,
            avgTargetCalories: Int(avgTarget.rounded()),
            avgCaloriePercent: avgTarget > 0 ? Int((Double(avgCalories) / avgTarget * 100).rounded()) : 0
        )
    }

    // FRG-304 — refreshes both readouts from HealthKit; safe to call repeatedly (e.g. on
    // foreground) since each fetch is a fresh query, not a subscription.
    func syncHealthKit() async {
        async let steps = HealthKitManager.shared.fetchTodayStepCount()
        async let sleep = HealthKitManager.shared.fetchLastNightSleepHours()
        stepsToday = await steps
        lastNightSleepHours = await sleep
    }

    // Feature request — "users should have the option to reset their profile which basically gives
    // them a fresh profile" — v2 clarified this should wipe the current Train/Eat/Progress data in
    // place rather than sign the user back out to onboarding, so `profile`/`program` themselves are
    // untouched here; only history/logs reset. Deliberately does not touch
    // CustomExerciseStore/CustomFoodStore/RecipeStore — those are per-device library content the
    // user built up, not profile/history data.
    func resetProfile() async {
        await CloudKitStore.shared.deleteHistoryKeepingProfile()
        await SyncQueue.shared.clearPending()
        LocalHistoryStore.clear()
        WorkoutDraftStore.clear()

        trailingSessions = []
        lastCompletedSession = nil
        mealEntries = [.breakfast: [], .lunch: [], .dinner: [], .snacks: []]
        bodyweightLogLb = [(Date(), profile.weightKg / 0.45359237)]
        workoutStartedAt = nil
        currentProgramDayIndex = 0
        programStartDate = Date()
        activeWeek = 1
        todaysExercises = Self.buildExerciseSlots(for: program, week: 1, dayIndex: 0)
        persistLocalHistory()

        await SyncQueue.shared.enqueue(.profile(
            profile: profile, program: program, savedPrograms: savedPrograms,
            dayIndex: currentProgramDayIndex, programStartDate: programStartDate
        ))
        await SyncQueue.shared.enqueue(.bodyweightLog(bodyweightLogLb.map { BodyweightEntry(date: $0.date, weightLb: $0.weightLb) }))
        await SyncQueue.shared.enqueue(.foodDay(dayKey: DayKey.today, entries: mealEntries))
        await SyncQueue.shared.enqueue(.workoutSessions([]))
    }
}
