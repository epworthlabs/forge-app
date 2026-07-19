import Foundation

/// Schema matches free-exercise-db (public domain / Unlicense) exactly — no attribution required,
/// but keep the field names aligned so re-syncing the upstream dataset stays a drop-in replace.
public struct Exercise: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let force: String?
    public let level: String
    public let mechanic: String?
    public let equipment: String?
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    public let instructions: [String]
    public let category: String
    public let images: [String]
}

public enum ExerciseLibrary {
    public static let all: [Exercise] = {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let exercises = try? JSONDecoder().decode([Exercise].self, from: data)
        else { return [] }
        return exercises
    }()

    public static func search(_ query: String) -> [Exercise] {
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) }
    }

    public static func byEquipment(_ equipment: String) -> [Exercise] {
        all.filter { $0.equipment == equipment }
    }
}
