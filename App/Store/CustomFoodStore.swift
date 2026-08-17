import Foundation
import ForgeCore

/// Feature request — "I want users to be able to add their own foods on their own devices, don't
/// make it publicly shared though, we don't know how reliable their inputs are." Distinct from
/// `CuratedFoodLibrary`, which *is* shared with every user, but only ever hand-edited by the
/// developer.
///
/// Bug fix — "when I reinstall the app, it doesn't remember my custom food." This used to be
/// Application Support-only, which is wiped along with the rest of the app's local container on
/// uninstall. Now synced through `SyncQueue`/`CloudKitStore`, same fix already applied to
/// `RecipeStore` for the identical complaint — still private (CloudKit's private database is never
/// shared with other users, so one user's possibly-wrong entry still never ends up in another
/// user's search results), it just also survives a reinstall. The local JSON cache stays too, so
/// foods are still available instantly offline.
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
        let snapshot = foods
        Task { await SyncQueue.shared.enqueue(.customFoods(snapshot)) }
        return food
    }

    func remove(_ food: FoodSearchResult) {
        foods.removeAll { $0.id == food.id }
        persist()
        let snapshot = foods
        Task { await SyncQueue.shared.enqueue(.customFoods(snapshot)) }
    }

    // App Store Guideline 5.1.1(v) — account deletion. Local-only, no CloudKit push: the server
    // record is deleted directly by `CloudKitStore.deleteAllData`.
    func clearAll() {
        foods = []
        persist()
    }

    // Bug fix — backfills custom foods for a returning user (or a fresh reinstall) from CloudKit.
    // Called once after sign-in, same pattern as `RecipeStore.loadFromCloudKit`. Merges rather than
    // overwrites: a food added while offline (queued in SyncQueue, not yet actually saved to
    // CloudKit) would otherwise vanish the moment this fetch runs and replaces `foods` outright. If
    // the merge found local-only foods the server doesn't have, push the union back up so the
    // server heals too.
    func loadFromCloudKit() async {
        guard let fetched = try? await CloudKitStore.shared.fetchCustomFoods() else {
            print("[CloudKit] custom foods fetch failed")
            return
        }
        let fetchedIDs = Set(fetched.map(\.id))
        let localOnly = foods.filter { !fetchedIDs.contains($0.id) }
        foods = fetched + localOnly
        persist()
        if !localOnly.isEmpty {
            let snapshot = foods
            Task { await SyncQueue.shared.enqueue(.customFoods(snapshot)) }
        }
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
