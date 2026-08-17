import Foundation
import ForgeCore

/// Feature request — the bundled 873-exercise library won't have everything (a gym-specific
/// machine, a niche variation), so this lets a user add their own.
///
/// Bug fix — "when I reinstall the app, it doesn't remember my custom workouts." This used to be
/// Application Support-only, which is wiped along with the rest of the app's local container on
/// uninstall. Now synced through `SyncQueue`/`CloudKitStore`, same fix already applied to
/// `RecipeStore` for the identical complaint — still private (CloudKit's private database is never
/// shared with other users), so this doesn't reopen the "don't make it publicly shared" concern,
/// it just also survives a reinstall. The local JSON cache stays too, so exercises are still
/// available instantly offline.
@MainActor
final class CustomExerciseStore: ObservableObject {
    static let shared = CustomExerciseStore()

    @Published private(set) var exercises: [Exercise] = []
    private let storageURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("custom_exercises.json")
        exercises = Self.load(from: storageURL)
    }

    func search(_ query: String) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        let q = query.lowercased()
        return exercises.filter { $0.name.lowercased().contains(q) }
    }

    func exercise(named name: String) -> Exercise? {
        exercises.first { $0.name == name }
    }

    @discardableResult
    func add(name: String, equipment: String?) -> Exercise {
        let trimmedEquipment = equipment?.trimmingCharacters(in: .whitespaces)
        let exercise = Exercise(
            id: "custom-\(UUID().uuidString)", name: name, force: nil, level: "custom", mechanic: nil,
            equipment: (trimmedEquipment?.isEmpty ?? true) ? nil : trimmedEquipment,
            primaryMuscles: [], secondaryMuscles: [], instructions: [], category: "custom", images: []
        )
        exercises.append(exercise)
        persist()
        let snapshot = exercises
        Task { await SyncQueue.shared.enqueue(.customExercises(snapshot)) }
        return exercise
    }

    // App Store Guideline 5.1.1(v) — account deletion. Local-only, no CloudKit push: the server
    // record is deleted directly by `CloudKitStore.deleteAllData`.
    func clearAll() {
        exercises = []
        persist()
    }

    // Bug fix — backfills custom exercises for a returning user (or a fresh reinstall) from
    // CloudKit. Called once after sign-in, same pattern as `RecipeStore.loadFromCloudKit`. Merges
    // rather than overwrites: an exercise added while offline (queued in SyncQueue, not yet
    // actually saved to CloudKit) would otherwise vanish the moment this fetch runs and replaces
    // `exercises` outright. If the merge found local-only exercises the server doesn't have, push
    // the union back up so the server heals too.
    func loadFromCloudKit() async {
        guard let fetched = try? await CloudKitStore.shared.fetchCustomExercises() else {
            print("[CloudKit] custom exercises fetch failed")
            return
        }
        let fetchedIDs = Set(fetched.map(\.id))
        let localOnly = exercises.filter { !fetchedIDs.contains($0.id) }
        exercises = fetched + localOnly
        persist()
        if !localOnly.isEmpty {
            let snapshot = exercises
            Task { await SyncQueue.shared.enqueue(.customExercises(snapshot)) }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(exercises) else { return }
        try? data.write(to: storageURL)
    }

    private static func load(from url: URL) -> [Exercise] {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Exercise].self, from: data) else { return [] }
        return decoded
    }
}
