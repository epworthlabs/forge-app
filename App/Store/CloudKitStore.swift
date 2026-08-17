import Foundation
import CloudKit
import ForgeCore

/// FRG-130/131 — private CloudKit database only (this is per-user data, never shared/public).
///
/// ROOT-CAUSE fix (FRG-383) — "when a new day rolls over / when I uninstall, my workouts, weight,
/// and recipes are all gone." Every history *read* here used to go through `CKQuery` — either
/// `NSPredicate(value: true)` (sessions, bodyweight, recipes) or a date-range predicate (food).
/// Both query forms require indexes configured manually in the CloudKit Dashboard: a date
/// predicate needs the `date` field marked Queryable (a step this file's old header admitted was
/// pending), and `NSPredicate(value: true)` needs the *recordName* system field marked Queryable —
/// which CloudKit does not auto-create and the Dashboard doesn't even surface prominently. Neither
/// was ever configured, so every fetch threw, every call site's `try?` swallowed it, and the app
/// started empty on each cold launch — while *saves* kept succeeding (schema auto-creates on first
/// save), which is why the user's profile (fetched by ID, no query, no index needed) always
/// survived reinstall while everything else vanished. The data was reaching the server and then
/// being unreachable.
///
/// The fix removes queries entirely: every domain is now stored the way the always-working profile
/// record is — a fixed, predictable record ID holding the domain's data as one JSON blob, fetched
/// directly by ID (`database.record(for:)` / `records(for:)`), which requires no Dashboard
/// configuration whatsoever, in Development or Production. Sessions chunk by calendar year (1MB
/// record cap headroom), food chunks by day (its natural access pattern), bodyweight and recipes
/// are single records. Old per-entry records from the query era remain orphaned on the server —
/// they were unreachable anyway and are harmless.
actor CloudKitStore {
    static let shared = CloudKitStore()

    private let container = CKContainer(identifier: "iCloud.com.epworthlabs.forge")
    private var database: CKDatabase { container.privateCloudDatabase }

    private init() {}

    // Bug fix — "the workouts/weight/recipes I logged are gone after a day rolls over or I
    // reinstall." Every save/fetch in this file has always swallowed its error via `try?` at the
    // call site, so there was never any visibility into *why* a write didn't reach CloudKit —
    // every previous fix in this area was a guess at the cause, not a confirmed diagnosis. The
    // single most common reason CloudKit silently does nothing: no iCloud account signed in on the
    // device (or restricted/degraded in some way) — `enqueue`/`flush` still "succeed" from the
    // app's point of view (nothing throws until the actual network call), so nothing in the UI
    // ever surfaced this. Exposed so the app can check it directly and warn rather than silently
    // losing data with no explanation.
    func accountStatus() async -> CKAccountStatus {
        (try? await container.accountStatus()) ?? .couldNotDetermine
    }

    // MARK: Profile — a single fixed-ID record, upserted in place rather than queried.

    private static let profileRecordID = CKRecord.ID(recordName: "profile")

    func saveProfile(_ profile: UserProfile, program: ProgramTemplate, savedPrograms: [ProgramTemplate], dayIndex: Int, programStartDate: Date) async throws {
        let record = (try? await database.record(for: Self.profileRecordID)) ?? CKRecord(recordType: "Profile", recordID: Self.profileRecordID)
        record["weightKg"] = profile.weightKg
        record["heightCm"] = profile.heightCm
        record["age"] = profile.age
        record["sex"] = profile.sex.rawValue
        record["activityLevel"] = profile.activityLevel.rawValue
        record["goal"] = profile.goal.rawValue
        record["fatFreeMassKg"] = profile.fatFreeMassKg
        // Feature request — target weight + timeframe drive the calorie deficit/surplus directly
        // (see TDEECalculator.goalAdjustedTDEE); additive fields, same as savedProgramsJSON above.
        record["targetWeightKg"] = profile.targetWeightKg
        record["targetWeeks"] = profile.targetWeeks
        // Feature request — manual macro split override; additive fields, same as target weight/weeks above.
        record["manualProteinPercent"] = profile.manualProteinPercent
        record["manualCarbPercent"] = profile.manualCarbPercent
        record["manualFatPercent"] = profile.manualFatPercent
        // Feature request — ProgramTemplate grew a sparse per-week override dictionary (for
        // "customize or copy to future weeks"), so it's encoded as one JSON blob rather than
        // exploded into individual fields — simpler and doesn't need a new CKRecord field every
        // time the program's shape grows. Always read/written as a whole, never queried piecemeal.
        record["programJSON"] = try JSONEncoder().encode(program)
        // Feature request — "select which workout program... especially if they have multiple."
        // The full library, `program` is just whichever entry is active. New field, additive —
        // old records simply won't have it (see the graceful fallback in fetchProfile below).
        record["savedProgramsJSON"] = try JSONEncoder().encode(savedPrograms)
        record["currentProgramDayIndex"] = dayIndex
        record["programStartDate"] = programStartDate
        _ = try await database.save(record)
    }

    func fetchProfile() async throws -> (profile: UserProfile, program: ProgramTemplate, savedPrograms: [ProgramTemplate], dayIndex: Int, programStartDate: Date)? {
        guard let record = try? await database.record(for: Self.profileRecordID),
              let weightKg = record["weightKg"] as? Double,
              let heightCm = record["heightCm"] as? Double,
              let age = record["age"] as? Int,
              let sexRaw = record["sex"] as? String, let sex = Sex(rawValue: sexRaw),
              let activityRaw = record["activityLevel"] as? Double, let activityLevel = ActivityLevel(rawValue: activityRaw),
              let goalRaw = record["goal"] as? String, let goal = Goal(rawValue: goalRaw),
              let programData = record["programJSON"] as? Data,
              let program = try? JSONDecoder().decode(ProgramTemplate.self, from: programData)
        else { return nil }

        let profile = UserProfile(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex, activityLevel: activityLevel,
                                   goal: goal, fatFreeMassKg: record["fatFreeMassKg"] as? Double,
                                   targetWeightKg: record["targetWeightKg"] as? Double, targetWeeks: record["targetWeeks"] as? Int,
                                   manualProteinPercent: record["manualProteinPercent"] as? Double,
                                   manualCarbPercent: record["manualCarbPercent"] as? Double,
                                   manualFatPercent: record["manualFatPercent"] as? Double)
        // Older records predate savedProgramsJSON entirely — default to a single-program library
        // rather than failing the whole fetch over one missing optional field.
        let savedPrograms: [ProgramTemplate]
        if let savedProgramsData = record["savedProgramsJSON"] as? Data,
           let decoded = try? JSONDecoder().decode([ProgramTemplate].self, from: savedProgramsData) {
            savedPrograms = decoded
        } else {
            savedPrograms = [program]
        }
        let dayIndex = record["currentProgramDayIndex"] as? Int ?? 0
        let programStartDate = record["programStartDate"] as? Date ?? Date()
        return (profile, program, savedPrograms, dayIndex, programStartDate)
    }

    // MARK: Workout sessions — full history as JSON, one fixed-ID record per calendar year
    // (fetched directly by ID, no query), chunked so a heavy multi-year history can't hit the
    // 1MB-per-record cap.

    private static func sessionsRecordID(year: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "workoutSessions-\(year)")
    }

    func saveAllWorkoutSessions(_ sessions: [WorkoutSession]) async throws {
        let byYear = Dictionary(grouping: sessions) { Calendar.current.component(.year, from: $0.date) }
        for (year, yearSessions) in byYear {
            let recordID = Self.sessionsRecordID(year: year)
            let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: "WorkoutSessionsByYear", recordID: recordID)
            // Union with whatever the server already has, by session id — sessions are append-only
            // in this app (no delete-a-session feature), so a device that saves before its own
            // fetch completed (fresh install, transient fetch failure) can't clobber history it
            // hasn't seen yet.
            var merged = yearSessions
            if let existingData = record["sessionsJSON"] as? Data,
               let existing = try? JSONDecoder().decode([WorkoutSession].self, from: existingData) {
                let ids = Set(merged.map(\.id))
                merged += existing.filter { !ids.contains($0.id) }
            }
            record["sessionsJSON"] = try JSONEncoder().encode(merged.sorted { $0.date < $1.date })
            _ = try await database.save(record)
        }
    }

    func fetchAllWorkoutSessions() async throws -> [WorkoutSession] {
        // Ten year-records covers any plausible history; missing years just come back as
        // per-ID unknownItem results and are skipped.
        let currentYear = Calendar.current.component(.year, from: Date())
        let ids = ((currentYear - 9)...currentYear).map { Self.sessionsRecordID(year: $0) }
        let results = try await database.records(for: ids)
        var all: [WorkoutSession] = []
        for (_, result) in results {
            guard let record = try? result.get(),
                  let data = record["sessionsJSON"] as? Data,
                  let sessions = try? JSONDecoder().decode([WorkoutSession].self, from: data)
            else { continue }
            all += sessions
        }
        return all.sorted { $0.date < $1.date }
    }

    // MARK: Food — one fixed-ID record per calendar day ("food-2026-07-25") holding that day's
    // whole diary as JSON. The day key doubles as the record name, so any day is fetchable
    // directly by ID; edits and deletes just re-save the whole (small) day.

    private static func foodDayRecordID(_ dayKey: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "food-\(dayKey)")
    }

    func saveFoodDay(dayKey: String, entries: [Meal: [FoodEntry]]) async throws {
        let recordID = Self.foodDayRecordID(dayKey)
        let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: "FoodDay", recordID: recordID)
        // Whole-day replace, deliberately not a union — entries are deletable, and a union would
        // resurrect deleted ones. Day-scoped, so the clobber blast radius is one day's diary.
        record["entriesJSON"] = try JSONEncoder().encode(entries)
        _ = try await database.save(record)
    }

    /// Missing record decodes as an empty day (genuinely nothing logged) — distinct from a thrown
    /// error (network/account trouble), which callers should treat as "unknown," not "empty."
    func fetchFoodDay(dayKey: String) async throws -> [Meal: [FoodEntry]] {
        do {
            let record = try await database.record(for: Self.foodDayRecordID(dayKey))
            guard let data = record["entriesJSON"] as? Data else { return [:] }
            return (try? JSONDecoder().decode([Meal: [FoodEntry]].self, from: data)) ?? [:]
        } catch let error as CKError where error.code == .unknownItem {
            return [:]
        }
    }

    /// Batch form for CSV export / weekly summaries — chunked to stay under CloudKit's per-op
    /// record limits.
    func fetchFoodDays(dayKeys: [String]) async throws -> [String: [Meal: [FoodEntry]]] {
        var out: [String: [Meal: [FoodEntry]]] = [:]
        var index = 0
        while index < dayKeys.count {
            let chunk = Array(dayKeys[index..<min(index + 100, dayKeys.count)])
            index += 100
            let results = try await database.records(for: chunk.map(Self.foodDayRecordID))
            for (recordID, result) in results {
                guard let record = try? result.get(),
                      let data = record["entriesJSON"] as? Data,
                      let entries = try? JSONDecoder().decode([Meal: [FoodEntry]].self, from: data)
                else { continue }
                out[String(recordID.recordName.dropFirst("food-".count))] = entries
            }
        }
        return out
    }

    // MARK: Bodyweight — the whole log as JSON on one fixed-ID record, fetched directly by ID.

    private static let bodyweightRecordID = CKRecord.ID(recordName: "bodyweightLog")

    func saveBodyweightLog(_ entries: [BodyweightEntry]) async throws {
        let record = (try? await database.record(for: Self.bodyweightRecordID)) ?? CKRecord(recordType: "BodyweightLog", recordID: Self.bodyweightRecordID)
        // Union by timestamp — weigh-ins are append-only (no delete UI), same clobber-guard
        // reasoning as saveAllWorkoutSessions.
        var merged = entries
        if let data = record["entriesJSON"] as? Data,
           let existing = try? JSONDecoder().decode([BodyweightEntry].self, from: data) {
            let stamps = Set(merged.map(\.date))
            merged += existing.filter { !stamps.contains($0.date) }
        }
        record["entriesJSON"] = try JSONEncoder().encode(merged.sorted { $0.date < $1.date })
        _ = try await database.save(record)
    }

    func fetchBodyweightLog() async throws -> [BodyweightEntry] {
        do {
            let record = try await database.record(for: Self.bodyweightRecordID)
            guard let data = record["entriesJSON"] as? Data else { return [] }
            return ((try? JSONDecoder().decode([BodyweightEntry].self, from: data)) ?? []).sorted { $0.date < $1.date }
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
    }

    // MARK: Recipes — the whole library as JSON on one fixed-ID record, fetched directly by ID.

    private static let recipesRecordID = CKRecord.ID(recordName: "recipes")

    func saveRecipes(_ recipes: [Recipe]) async throws {
        let record = (try? await database.record(for: Self.recipesRecordID)) ?? CKRecord(recordType: "RecipeList", recordID: Self.recipesRecordID)
        // Whole-list replace, not a union — recipes are deletable, and a union would resurrect
        // deleted ones. RecipeStore's merge-on-load covers the fresh-install direction instead.
        record["recipesJSON"] = try JSONEncoder().encode(recipes)
        _ = try await database.save(record)
    }

    func fetchRecipes() async throws -> [Recipe] {
        do {
            let record = try await database.record(for: Self.recipesRecordID)
            guard let data = record["recipesJSON"] as? Data else { return [] }
            return (try? JSONDecoder().decode([Recipe].self, from: data)) ?? []
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
    }

    // MARK: Custom exercises/foods — same whole-blob-on-a-fixed-ID pattern as Recipes.
    //
    // Bug fix — "when I reinstall the app, it doesn't remember my custom workouts or my food."
    // These used to be Application Support-only (see CustomExerciseStore/CustomFoodStore's old
    // header comments), which is wiped along with the rest of the app's local container on
    // uninstall — same root cause FRG-383 already fixed for recipes/sessions/bodyweight. The
    // private CloudKit database is still never shared with other users (or exposed publicly), so
    // this doesn't reopen the "don't make it publicly shared" concern that motivated device-local
    // storage in the first place — it only means a reinstall (or another of the user's own signed-in
    // devices) now recovers this data too.

    private static let customExercisesRecordID = CKRecord.ID(recordName: "customExercises")

    func saveCustomExercises(_ exercises: [Exercise]) async throws {
        let record = (try? await database.record(for: Self.customExercisesRecordID)) ?? CKRecord(recordType: "CustomExerciseList", recordID: Self.customExercisesRecordID)
        // Whole-list replace, not a union — custom exercises are deletable, and a union would
        // resurrect deleted ones. CustomExerciseStore's merge-on-load covers the fresh-install
        // direction instead.
        record["exercisesJSON"] = try JSONEncoder().encode(exercises)
        _ = try await database.save(record)
    }

    func fetchCustomExercises() async throws -> [Exercise] {
        do {
            let record = try await database.record(for: Self.customExercisesRecordID)
            guard let data = record["exercisesJSON"] as? Data else { return [] }
            return (try? JSONDecoder().decode([Exercise].self, from: data)) ?? []
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
    }

    private static let customFoodsRecordID = CKRecord.ID(recordName: "customFoods")

    func saveCustomFoods(_ foods: [FoodSearchResult]) async throws {
        let record = (try? await database.record(for: Self.customFoodsRecordID)) ?? CKRecord(recordType: "CustomFoodList", recordID: Self.customFoodsRecordID)
        record["foodsJSON"] = try JSONEncoder().encode(foods)
        _ = try await database.save(record)
    }

    func fetchCustomFoods() async throws -> [FoodSearchResult] {
        do {
            let record = try await database.record(for: Self.customFoodsRecordID)
            guard let data = record["foodsJSON"] as? Data else { return [] }
            return (try? JSONDecoder().decode([FoodSearchResult].self, from: data)) ?? []
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
    }

    // MARK: Profile reset

    /// Feature request — "users should have the option to reset their profile which basically
    /// gives them a fresh profile" — later clarified (v2) to mean wiping Train/Eat/Progress data in
    /// place, not actually signing the user out to onboarding. Deletes every year-chunked workout
    /// session record, the bodyweight log, and a trailing window of food-day records — deliberately
    /// leaves the profile record itself alone (the caller re-saves it with reset progress fields
    /// right after this returns) and does *not* touch recipes/custom exercises/custom foods, which
    /// are per-device library content, not "profile" data.
    ///
    /// Bug fix — "the stats for this week under Progress don't reset, prob because my food logged
    /// from prev days didn't reset." Originally this only deleted *today's* food-day record — food
    /// days are keyed one-per-calendar-day with no way to enumerate which ones actually have data
    /// without reintroducing the `CKQuery` mechanism this file's header explains was deliberately
    /// removed, so "delete all of them" isn't directly expressible. The fix takes the same approach
    /// `CSVExporter` already uses for "full nutrition history": a deterministic, client-computed
    /// window of the last 365 day-keys, covering any realistic lookback (`nutritionWeekSummary`
    /// only reads the last 7). Batched via `modifyRecords` (not one `deleteRecord` await per day)
    /// so this doesn't turn into hundreds of sequential round-trips; `atomically: false` means one
    /// already-missing day in a batch doesn't fail the rest.
    func deleteHistoryKeepingProfile() async {
        await deleteHistoryRecords()
    }

    // Shared by `deleteHistoryKeepingProfile` (profile reset) and `deleteAllData` (account
    // deletion) — bodyweight, year-chunked sessions, and a trailing food-day window, the same
    // "history" scope either way.
    private func deleteHistoryRecords() async {
        var idsToDelete = [Self.bodyweightRecordID]
        let currentYear = Calendar.current.component(.year, from: Date())
        idsToDelete += ((currentYear - 9)...currentYear).map(Self.sessionsRecordID(year:))
        for id in idsToDelete {
            _ = try? await database.deleteRecord(withID: id)
        }

        let dayKeys = (0..<365).compactMap { offset -> String? in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date()).map(DayKey.string(for:))
        }
        let foodDayIDs = dayKeys.map(Self.foodDayRecordID)
        var index = 0
        while index < foodDayIDs.count {
            let chunk = Array(foodDayIDs[index..<min(index + 100, foodDayIDs.count)])
            index += 100
            _ = try? await database.modifyRecords(saving: [], deleting: chunk, atomically: false)
        }
    }

    // MARK: Account deletion

    /// App Store Guideline 5.1.1(v) — "apps that support account creation must also offer the
    /// ability to initiate deletion of their account from within the app." Sign in with Apple +
    /// this private CloudKit database is this app's account, so deletion means every record this
    /// file ever writes, not just the history `deleteHistoryKeepingProfile` covers for profile
    /// reset — profile, recipes, and custom exercises/foods too, none of which "reset" touches on
    /// purpose (see that function's doc comment). `AppStore.deleteAccount` is the full orchestration
    /// (this plus clearing local caches/SyncQueue/sign-in state); this method only owns the server side.
    func deleteAllData() async {
        await deleteHistoryRecords()
        let idsToDelete = [Self.profileRecordID, Self.recipesRecordID, Self.customExercisesRecordID, Self.customFoodsRecordID]
        for id in idsToDelete {
            do {
                _ = try await database.deleteRecord(withID: id)
            } catch let error as CKError where error.code == .unknownItem {
                // Already gone (or never existed) — not a failure.
            } catch {
                // Bug fix — this used to be a bare `try?`, so a failed profile deletion (network
                // blip, CloudKit environment mismatch, etc.) was indistinguishable from success:
                // the record would silently survive, `fetchProfile()` on the next sign-in would
                // still find it, and "delete my account" would look like it did nothing at all.
                // Surfaced so that failure mode is at least visible in device logs instead of
                // silently mimicking a successful deletion.
                print("[CloudKit] account deletion failed for \(id.recordName): \(error)")
            }
        }
    }
}
