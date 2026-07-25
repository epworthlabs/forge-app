import Foundation
import ForgeCore

/// Feature request — "I want users to be able to add their own foods on their own devices, don't
/// make it publicly shared though, we don't know how reliable their inputs are." Same tradeoff
/// `CustomExerciseStore` already makes for its own device-local additions: persisted locally
/// (Application Support), never synced through `SyncQueue`/CloudKit — so one user's possibly-wrong
/// entry never ends up in another user's search results. Distinct from `CuratedFoodLibrary`,
/// which *is* shared with every user, but only ever hand-edited by the developer.
@MainActor
final class CustomFoodStore: ObservableObject {
    static let shared = CustomFoodStore()

    @Published private(set) var foods: [FoodSearchResult] = []
    private let storageURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("custom_foods.json")
        foods = Self.load(from: storageURL)
    }

    func search(_ query: String) -> [FoodSearchResult] {
        guard !query.isEmpty else { return foods }
        let q = query.lowercased()
        return foods.filter { $0.name.lowercased().contains(q) || ($0.brand?.lowercased().contains(q) ?? false) }
    }

    @discardableResult
    func add(name: String, brand: String?, kcal: Int, proteinG: Double, carbG: Double, fatG: Double, servingDescription: String) -> FoodSearchResult {
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespaces)
        let food = FoodSearchResult(
            id: "custom-\(UUID().uuidString)", name: name, brand: (trimmedBrand?.isEmpty ?? true) ? nil : trimmedBrand,
            kcal: kcal, proteinG: proteinG, carbG: carbG, fatG: fatG, servingDescription: servingDescription, source: .custom
        )
        foods.append(food)
        persist()
        return food
    }

    func remove(_ food: FoodSearchResult) {
        foods.removeAll { $0.id == food.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(foods) else { return }
        try? data.write(to: storageURL)
    }

    private static func load(from url: URL) -> [FoodSearchResult] {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([FoodSearchResult].self, from: data) else { return [] }
        return decoded
    }
}
