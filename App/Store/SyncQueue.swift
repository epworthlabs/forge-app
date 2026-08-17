import Foundation
import Network
import UIKit
import ForgeCore

/// FRG-114 — every CloudKit write used to be `Task { try? await CloudKitStore.shared.saveX(...) }`:
/// errors were silently swallowed with no retry, so a write attempted in a gym dead zone was just
/// lost forever. `SyncQueue` is what "sync once connectivity returns" actually requires: failed
/// writes persist to disk (survives the app being force-quit while offline, not just backgrounded)
/// and retry automatically once the network comes back or the app returns to the foreground.
// Root-cause fix (FRG-383) — every case now carries the domain's *entire current state* rather
// than a single entry, matching CloudKitStore's redesign onto fixed-ID whole-blob records (see
// its header). That also makes queued retries self-coalescing: two queued writes of the same kind
// are strictly redundant, so `coalesceIntoPending` below keeps only the newest. Per-entry delete
// cases are gone — a delete is just the next whole-state save without the entry.
// Synthesized Codable (all payloads are Codable); a persisted queue file from the old per-entry
// format fails to decode and is discarded, which is safe — those writes targeted record types the
// app no longer reads.
enum PendingWrite: Codable {
    case profile(profile: UserProfile, program: ProgramTemplate, savedPrograms: [ProgramTemplate], dayIndex: Int, programStartDate: Date)
    case workoutSessions([WorkoutSession])
    case foodDay(dayKey: String, entries: [Meal: [FoodEntry]])
    case bodyweightLog([BodyweightEntry])
    case recipes([Recipe])
    case customExercises([Exercise])
    case customFoods([FoodSearchResult])
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
            coalesceIntoPending(write)
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

    // Feature request — "reset their profile." Without this, a write queued while offline (e.g. a
    // profile save) could resurrect the very data `AppStore.resetProfile()` just deleted the next
    // time this flushes.
    func clearPending() {
        pending.removeAll()
        persist()
    }

    private func perform(_ write: PendingWrite) async throws {
        switch write {
        case .profile(let profile, let program, let savedPrograms, let dayIndex, let programStartDate):
            try await CloudKitStore.shared.saveProfile(profile, program: program, savedPrograms: savedPrograms, dayIndex: dayIndex, programStartDate: programStartDate)
        case .workoutSessions(let sessions):
            try await CloudKitStore.shared.saveAllWorkoutSessions(sessions)
        case .foodDay(let dayKey, let entries):
            try await CloudKitStore.shared.saveFoodDay(dayKey: dayKey, entries: entries)
        case .bodyweightLog(let entries):
            try await CloudKitStore.shared.saveBodyweightLog(entries)
        case .recipes(let recipes):
            try await CloudKitStore.shared.saveRecipes(recipes)
        case .customExercises(let exercises):
            try await CloudKitStore.shared.saveCustomExercises(exercises)
        case .customFoods(let foods):
            try await CloudKitStore.shared.saveCustomFoods(foods)
        }
    }

    // Whole-state writes make older queued writes of the same kind strictly redundant — a
    // newer snapshot supersedes them entirely. Drop them so an extended offline stretch queues
    // a handful of entries, not hundreds.
    private func coalesceIntoPending(_ write: PendingWrite) {
        pending.removeAll { existing in
            switch (existing, write) {
            case (.profile, .profile), (.workoutSessions, .workoutSessions),
                 (.bodyweightLog, .bodyweightLog), (.recipes, .recipes),
                 (.customExercises, .customExercises), (.customFoods, .customFoods):
                return true
            case (.foodDay(let existingKey, _), .foodDay(let newKey, _)):
                return existingKey == newKey
            default:
                return false
            }
        }
        pending.append(write)
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
