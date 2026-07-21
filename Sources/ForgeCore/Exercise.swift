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

    // Explicit public init — without one, Swift's synthesized memberwise init for a public struct
    // is only internal, so App-layer code (e.g. adding a custom exercise) couldn't construct an
    // Exercise at all. JSON decoding of the bundled dataset doesn't need this (it happens inside
    // this module), but anything built outside ForgeCore does.
    public init(id: String, name: String, force: String?, level: String, mechanic: String?, equipment: String?,
                primaryMuscles: [String], secondaryMuscles: [String], instructions: [String], category: String, images: [String]) {
        self.id = id
        self.name = name
        self.force = force
        self.level = level
        self.mechanic = mechanic
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
        self.category = category
        self.images = images
    }
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
