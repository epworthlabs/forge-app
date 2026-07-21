import Foundation
import Network
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
}

// Manual Codable — Swift doesn't synthesize Codable for enums with associated values.
extension PendingWrite: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, profile, program, savedPrograms, dayIndex, programStartDate, session, entry, meal, date, weightLb
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
    func enqueue(_ write: PendingWrite) async {
        do {
            try await perform(write)
        } catch {
            pending.append(write)
            persist()
        }
    }

    /// Call on network restore and app foreground — covers both "was briefly offline mid-session"
    /// and "was force-quit offline, network came back while it wasn't running."
    func flush() async {
        guard !pending.isEmpty else { return }
        var remaining: [PendingWrite] = []
        for write in pending {
            do {
                try await perform(write)
            } catch {
                remaining.append(write)
            }
        }
        pending = remaining
        persist()
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
}
