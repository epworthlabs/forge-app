import Foundation
import CloudKit
import ForgeCore

/// FRG-130/131 — private CloudKit database only (this is per-user data, never shared/public).
/// Record types intentionally mirror the app's existing plain-struct model (`UserProfile`,
/// `WorkoutSession`, `FoodEntry`) rather than introducing a parallel schema, so there's one
/// source of truth for what a "profile" or "session" looks like — matches the README's
/// "swapping the storage underneath shouldn't change any view code" intent.
///
/// The `date` fields on WorkoutSession/FoodEntry/BodyweightEntry need to be marked Queryable
/// (and Sortable, for the bodyweight log) in the CloudKit Dashboard's Development schema before
/// the query methods below will work — CloudKit auto-creates a record type's schema on first
/// save, but querying/sorting by a custom field needs that field indexed explicitly. This is a
/// one-time manual step, not something `xcodebuild` or this code can configure remotely.
actor CloudKitStore {
    static let shared = CloudKitStore()

    private let container = CKContainer(identifier: "iCloud.com.epworthlabs.forge")
    private var database: CKDatabase { container.privateCloudDatabase }

    private init() {}

    // MARK: Profile — a single fixed-ID record, upserted in place rather than queried.

    private static let profileRecordID = CKRecord.ID(recordName: "profile")

    func saveProfile(_ profile: UserProfile, program: ProgramTemplate, dayIndex: Int, programStartDate: Date) async throws {
        let record = (try? await database.record(for: Self.profileRecordID)) ?? CKRecord(recordType: "Profile", recordID: Self.profileRecordID)
        record["weightKg"] = profile.weightKg
        record["heightCm"] = profile.heightCm
        record["age"] = profile.age
        record["sex"] = profile.sex.rawValue
        record["activityLevel"] = profile.activityLevel.rawValue
        record["goal"] = profile.goal.rawValue
        record["fatFreeMassKg"] = profile.fatFreeMassKg
        record["programID"] = program.id
        record["programName"] = program.name
        // FRG-104 — days carries the actual exercise content (curated or user-built); JSON-encoded
        // into one field rather than a child-record hierarchy, since a program's full day/exercise
        // list is small and always read/written as a whole, never queried piecemeal.
        record["programDaysJSON"] = try JSONEncoder().encode(program.days)
        record["programWeeks"] = program.weeks
        record["currentProgramDayIndex"] = dayIndex
        record["programDeloadEveryNWeeks"] = program.deloadEveryNWeeks
        record["programStartDate"] = programStartDate
        _ = try await database.save(record)
    }

    func fetchProfile() async throws -> (profile: UserProfile, program: ProgramTemplate, dayIndex: Int, programStartDate: Date)? {
        guard let record = try? await database.record(for: Self.profileRecordID),
              let weightKg = record["weightKg"] as? Double,
              let heightCm = record["heightCm"] as? Double,
              let age = record["age"] as? Int,
              let sexRaw = record["sex"] as? String, let sex = Sex(rawValue: sexRaw),
              let activityRaw = record["activityLevel"] as? Double, let activityLevel = ActivityLevel(rawValue: activityRaw),
              let goalRaw = record["goal"] as? String, let goal = Goal(rawValue: goalRaw),
              let programID = record["programID"] as? String,
              let programName = record["programName"] as? String,
              let programWeeks = record["programWeeks"] as? Int
        else { return nil }

        let profile = UserProfile(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex, activityLevel: activityLevel,
                                   goal: goal, fatFreeMassKg: record["fatFreeMassKg"] as? Double)
        let days: [ProgramDay]
        if let daysData = record["programDaysJSON"] as? Data, let decoded = try? JSONDecoder().decode([ProgramDay].self, from: daysData) {
            days = decoded
        } else {
            days = [] // records saved before FRG-104 won't have this field
        }
        let program = ProgramTemplate(id: programID, name: programName, weeks: programWeeks, days: days,
                                       deloadEveryNWeeks: record["programDeloadEveryNWeeks"] as? Int)
        let dayIndex = record["currentProgramDayIndex"] as? Int ?? 0
        let programStartDate = record["programStartDate"] as? Date ?? Date()
        return (profile, program, dayIndex, programStartDate)
    }

    // MARK: Workout sessions — sets serialized as JSON; a session is small enough that a child
    // record per set would be needless CloudKit round-trip overhead for no real benefit.

    func saveWorkoutSession(_ session: WorkoutSession) async throws {
        let record = CKRecord(recordType: "WorkoutSession")
        record["date"] = session.date
        record["setsJSON"] = try JSONEncoder().encode(session.sets)
        _ = try await database.save(record)
    }

    func fetchWorkoutSessions() async throws -> [WorkoutSession] {
        let query = CKQuery(recordType: "WorkoutSession", predicate: NSPredicate(value: true))
        let (matchResults, _) = try await database.records(matching: query)
        return matchResults.compactMap { _, result in
            guard let record = try? result.get(),
                  let date = record["date"] as? Date,
                  let setsData = record["setsJSON"] as? Data,
                  let sets = try? JSONDecoder().decode([SetLog].self, from: setsData)
            else { return nil }
            return WorkoutSession(date: date, sets: sets)
        }
    }

    // MARK: Food entries

    func saveFoodEntry(_ entry: FoodEntry, meal: Meal) async throws {
        let record = CKRecord(recordType: "FoodEntry")
        record["date"] = entry.date
        record["meal"] = meal.rawValue
        record["name"] = entry.name
        record["kcal"] = entry.kcal
        record["proteinG"] = entry.proteinG
        record["carbG"] = entry.carbG
        record["fatG"] = entry.fatG
        _ = try await database.save(record)
    }

    /// Fetches every FoodEntry between `start` and `end` — used both for "today's diary" (a
    /// one-day window) and CSV export (an open-ended historical window).
    func fetchFoodEntries(from start: Date, to end: Date) async throws -> [Meal: [FoodEntry]] {
        let predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        let query = CKQuery(recordType: "FoodEntry", predicate: predicate)
        let (matchResults, _) = try await database.records(matching: query)

        var byMeal: [Meal: [FoodEntry]] = [.breakfast: [], .lunch: [], .dinner: [], .snacks: []]
        for (_, result) in matchResults {
            guard let record = try? result.get(),
                  let mealRaw = record["meal"] as? String, let meal = Meal(rawValue: mealRaw),
                  let date = record["date"] as? Date,
                  let name = record["name"] as? String,
                  let kcal = record["kcal"] as? Int,
                  let proteinG = record["proteinG"] as? Int,
                  let carbG = record["carbG"] as? Int,
                  let fatG = record["fatG"] as? Int
            else { continue }
            byMeal[meal, default: []].append(FoodEntry(date: date, name: name, kcal: kcal, proteinG: proteinG, carbG: carbG, fatG: fatG))
        }
        return byMeal
    }

    // MARK: Bodyweight

    func saveBodyweightEntry(date: Date, weightLb: Double) async throws {
        let record = CKRecord(recordType: "BodyweightEntry")
        record["date"] = date
        record["weightLb"] = weightLb
        _ = try await database.save(record)
    }

    func fetchBodyweightLog() async throws -> [(date: Date, weightLb: Double)] {
        let query = CKQuery(recordType: "BodyweightEntry", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        let (matchResults, _) = try await database.records(matching: query)
        return matchResults.compactMap { _, result in
            guard let record = try? result.get(),
                  let date = record["date"] as? Date,
                  let weightLb = record["weightLb"] as? Double
            else { return nil }
            return (date: date, weightLb: weightLb)
        }
    }
}
