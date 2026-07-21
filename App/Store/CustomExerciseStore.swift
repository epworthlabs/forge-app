import Foundation
import ForgeCore

/// Feature request — the bundled 873-exercise library won't have everything (a gym-specific
/// machine, a niche variation), so this lets a user add their own. Persisted locally
/// (Application Support), not through CloudKit — scoped to this device for now, the same
/// tradeoff SyncQueue's pending-write file makes for its own storage; revisit if custom
/// exercises need to follow a user across devices.
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
        return exercise
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
