import Foundation
import Network
import UIKit
import ForgeCore

/// FRG-114 — every CloudKit write used to be `Task { try? await CloudKitStore.shared.saveX(...) }`:
/// errors were silently swallowed with no retry, so a write attempted in a gym dead zone was just
/// lost forever. `SyncQueue` is what "sync once connectivity returns" actually requires: failed
/// writes persist to disk (survives the app being force-quit while offline, not just backgrounded)
/// and retry automatically once the network comes back or the app returns to the foreground.
enum PendingWrite {
    case profile(profile: UserProfile, program: ProgramTemplate, savedPrograms: [ProgramTemplate], dayIndex: Int, programStartDate: Date)
    case workoutSession(WorkoutSession)
    case foodEntry(entry: FoodEntry, meal: Meal)
    case bodyweightEntry(date: Date, weightLb: Double)
    // Feature request — "the foods logged also need to be editable and deletable." `foodEntry`
    // above now upserts by the entry's own stable id (see CloudKitStore.saveFoodEntry), so it
    // already covers edits; this covers the delete half.
    case deleteFoodEntry(id: UUID)
    // Bug fix — "my recipes weren't saved [after reinstall]... make sure that saves even if the
    // app gets deleted." Same upsert-by-id / delete-by-id pattern as foodEntry above.
    case recipe(Recipe)
    case deleteRecipe(id: UUID)
}

// Manual Codable — Swift doesn't synthesize Codable for enums with associated values.
extension PendingWrite: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, profile, program, savedPrograms, dayIndex, programStartDate, session, entry, meal, date, weightLb, id, recipe
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .profile(let profile, let program, let savedPrograms, let dayIndex, let programStartDate):
            try container.encode("profile", forKey: .type)
            try container.encode(profile, forKey: .profile)
            try container.encode(program, forKey: .program)
            try container.encode(savedPrograms, forKey: .savedPrograms)
            try container.encode(dayIndex, forKey: .dayIndex)
            try container.encode(programStartDate, forKey: .programStartDate)
        case .workoutSession(let session):
            try container.encode("workoutSession", forKey: .type)
            try container.encode(session, forKey: .session)
        case .foodEntry(let entry, let meal):
            try container.encode("foodEntry", forKey: .type)
            try container.encode(entry, forKey: .entry)
            try container.encode(meal, forKey: .meal)
        case .bodyweightEntry(let date, let weightLb):
            try container.encode("bodyweightEntry", forKey: .type)
            try container.encode(date, forKey: .date)
            try container.encode(weightLb, forKey: .weightLb)
        case .deleteFoodEntry(let id):
            try container.encode("deleteFoodEntry", forKey: .type)
            try container.encode(id, forKey: .id)
        case .recipe(let recipe):
            try container.encode("recipe", forKey: .type)
            try container.encode(recipe, forKey: .recipe)
        case .deleteRecipe(let id):
            try container.encode("deleteRecipe", forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "profile":
            self = .profile(
                profile: try container.decode(UserProfile.self, forKey: .profile),
                program: try container.decode(ProgramTemplate.self, forKey: .program),
                savedPrograms: try container.decode([ProgramTemplate].self, forKey: .savedPrograms),
                dayIndex: try container.decode(Int.self, forKey: .dayIndex),
                programStartDate: try container.decode(Date.self, forKey: .programStartDate)
            )
        case "workoutSession":
            self = .workoutSession(try container.decode(WorkoutSession.self, forKey: .session))
        case "foodEntry":
            self = .foodEntry(entry: try container.decode(FoodEntry.self, forKey: .entry), meal: try container.decode(Meal.self, forKey: .meal))
        case "bodyweightEntry":
            self = .bodyweightEntry(date: try container.decode(Date.self, forKey: .date), weightLb: try container.decode(Double.self, forKey: .weightLb))
        case "deleteFoodEntry":
            self = .deleteFoodEntry(id: try container.decode(UUID.self, forKey: .id))
        case "recipe":
            self = .recipe(try container.decode(Recipe.self, forKey: .recipe))
        case "deleteRecipe":
            self = .deleteRecipe(id: try container.decode(UUID.self, forKey: .id))
        case let unknown:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown PendingWrite type: \(unknown)")
        }
    }
}

actor SyncQueue {
    static let shared = SyncQueue()

    private let storageURL: URL
    private var pending: [PendingWrite]
    private var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pending_sync_queue.json")
        storageURL = url
        pending = Self.load(from: url)

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { await self.handlePathUpdate(satisfied: path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "SyncQueue.NWPathMonitor"))
    }

    private func handlePathUpdate(satisfied: Bool) {
        let wasOffline = !isOnline
        isOnline = satisfied
        if satisfied && wasOffline {
            Task { await flush() }
        }
    }

    /// Tries immediately; only falls back to the persisted retry queue on failure, so the common
    /// case (online) isn't slowed down by queue bookkeeping.
    ///
    /// Bug fix — "when a new day rolls over, the workouts I completed / the weight I log are no
    /// longer recorded, this also happens when I uninstall the app." Every call site fires this
    /// from a bare `Task { await SyncQueue.shared.enqueue(...) }` — e.g. right after tapping
    /// "Finish Workout" or saving a weigh-in, exactly the moment a real user is likely to lock
    /// their phone or switch apps. If iOS suspends the process before that `Task` gets to run, the
    /// write is killed mid-flight: it never reaches either the success path or the `catch` that
    /// would queue it for retry, so it's lost with no trace — not a network failure `pending` can
    /// recover from, since it never got far enough to be recorded as failed. `beginBackgroundTask`
    /// asks iOS for extra time to finish in-flight work even after the app backgrounds, which is
    /// exactly what's needed here; without it, only writes that complete before backgrounding (or
    /// that already-thrown network errors get queued) survive, which reads exactly like "gone the
    /// moment I stop looking at the app."
    func enqueue(_ write: PendingWrite) async {
        let taskID = await Self.beginBackgroundTask()
        do {
            try await perform(write)
        } catch {
            // Bug fix — every failure here used to be swallowed with no trace at all, so there
            // was no way to actually confirm *why* a write never reached CloudKit versus just
            // guessing (no iCloud account, a container/entitlement problem, a genuine network
            // error, etc). Visible in Xcode's console / device logs the next time this is run.
            print("[SyncQueue] write failed, queued for retry: \(error)")
            pending.append(write)
            persist()
        }
        await Self.endBackgroundTask(taskID)
    }

    /// Call on network restore and app foreground — covers both "was briefly offline mid-session"
    /// and "was force-quit offline, network came back while it wasn't running." Same background-task
    /// protection as `enqueue` — a retry triggered right as the app resumes shouldn't be killable by
    /// the user backgrounding again a moment later, before the retry itself finishes.
    func flush() async {
        guard !pending.isEmpty else { return }
        let taskID = await Self.beginBackgroundTask()
        var remaining: [PendingWrite] = []
        for write in pending {
            do {
                try await perform(write)
            } catch {
                print("[SyncQueue] retry failed, still queued: \(error)")
                remaining.append(write)
            }
        }
        pending = remaining
        persist()
        await Self.endBackgroundTask(taskID)
    }

    var pendingCount: Int { pending.count }

    private func perform(_ write: PendingWrite) async throws {
        switch write {
        case .profile(let profile, let program, let savedPrograms, let dayIndex, let programStartDate):
            try await CloudKitStore.shared.saveProfile(profile, program: program, savedPrograms: savedPrograms, dayIndex: dayIndex, programStartDate: programStartDate)
        case .workoutSession(let session):
            try await CloudKitStore.shared.saveWorkoutSession(session)
        case .foodEntry(let entry, let meal):
            try await CloudKitStore.shared.saveFoodEntry(entry, meal: meal)
        case .bodyweightEntry(let date, let weightLb):
            try await CloudKitStore.shared.saveBodyweightEntry(date: date, weightLb: weightLb)
        case .deleteFoodEntry(let id):
            try await CloudKitStore.shared.deleteFoodEntry(id: id)
        case .recipe(let recipe):
            try await CloudKitStore.shared.saveRecipe(recipe)
        case .deleteRecipe(let id):
            try await CloudKitStore.shared.deleteRecipe(id: id)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: storageURL)
    }

    private static func load(from url: URL) -> [PendingWrite] {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([PendingWrite].self, from: data) else { return [] }
        return decoded
    }

    // `UIApplication` is main-actor-isolated; `SyncQueue` itself isn't, so these hop over rather
    // than requiring every caller to. The expiration handler ends the same identifier it was given
    // — standard `beginBackgroundTask` idiom for "the OS ran out of patience before we finished."
    @MainActor
    private static func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "SyncQueue.write") {
            UIApplication.shared.endBackgroundTask(taskID)
        }
        return taskID
    }

    @MainActor
    private static func endBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
    }
}
