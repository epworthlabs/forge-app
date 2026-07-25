import Foundation
import ForgeCore

/// Feature request — "I want users to be able to group a collection of foods and save + input it
/// as a recipe." A recipe's ingredients are kept only for display/editing context ("what's in
/// this") — logging one reuses the *entire* existing food pipeline unchanged by exposing the
/// recipe's per-serving macros as a plain `FoodSearchResult` (see `asFoodSearchResult` below):
/// `PortionConfirmSheet` already supports a freely-typed fractional "servings" quantity, so
/// `AppStore.logFood` never needs to know a recipe was involved at all.
///
/// Bug fix — "when I redownloaded the app, my recipes weren't saved... make sure that saves even
/// if the app gets deleted." This used to be device-local only (Application Support), the same
/// tradeoff `CustomFoodStore`/`CustomExerciseStore` make — reasonable for those two (explicitly
/// "don't make it publicly shared," and unreliable user-authored macro data), but a saved recipe
/// is a deliberate save the user expects to last, same category as workout sessions/food entries.
/// Now synced through `SyncQueue`/`CloudKitStore` (still private — CloudKit's private database is
/// never shared with other users, it just also survives a reinstall) — the local JSON cache stays
/// too, so recipes are still available instantly offline, but it's no longer the only copy.
struct RecipeIngredient: Identifiable, Codable {
    var id = UUID()
    var name: String
    var kcal: Int
    var proteinG: Double
    var carbG: Double
    var fatG: Double
}

struct Recipe: Identifiable, Codable {
    var id = UUID()
    var name: String
    /// How many servings this batch of ingredients yields — `asFoodSearchResult` divides the
    /// summed totals by this so "1 serving" of the recipe scales the same way any other food does.
    var servings: Int
    var ingredients: [RecipeIngredient]

    var totalKcal: Int { ingredients.reduce(0) { $0 + $1.kcal } }
    var totalProteinG: Double { ingredients.reduce(0) { $0 + $1.proteinG } }
    var totalCarbG: Double { ingredients.reduce(0) { $0 + $1.carbG } }
    var totalFatG: Double { ingredients.reduce(0) { $0 + $1.fatG } }

    var asFoodSearchResult: FoodSearchResult {
        let servingCount = max(1, servings)
        return FoodSearchResult(
            id: "recipe-\(id.uuidString)", name: name,
            kcal: Int((Double(totalKcal) / Double(servingCount)).rounded()),
            proteinG: totalProteinG / Double(servingCount),
            carbG: totalCarbG / Double(servingCount),
            fatG: totalFatG / Double(servingCount),
            servingDescription: servingCount == 1 ? "1 recipe (\(ingredients.count) ingredients)" : "1 of \(servingCount) servings",
            source: .recipe
        )
    }
}

@MainActor
final class RecipeStore: ObservableObject {
    static let shared = RecipeStore()

    @Published private(set) var recipes: [Recipe] = []
    private let storageURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("recipes.json")
        recipes = Self.load(from: storageURL)
    }

    func searchAsFoodResults(_ query: String) -> [FoodSearchResult] {
        let matches: [Recipe]
        if query.isEmpty {
            matches = recipes
        } else {
            let q = query.lowercased()
            matches = recipes.filter { $0.name.lowercased().contains(q) }
        }
        return matches.map(\.asFoodSearchResult)
    }

    func add(_ recipe: Recipe) {
        recipes.append(recipe)
        persist()
        Task { await SyncQueue.shared.enqueue(.recipe(recipe)) }
    }

    func remove(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        persist()
        Task { await SyncQueue.shared.enqueue(.deleteRecipe(id: recipe.id)) }
    }

    // Bug fix — backfills recipes for a returning user (or a fresh reinstall) from CloudKit.
    // Called once after sign-in, same "called once after construction, not from init" reasoning
    // as `AppStore.loadHistoryFromCloudKit`. Merges rather than overwrites: a recipe added while
    // offline (queued in SyncQueue, not yet actually saved to CloudKit) would otherwise vanish the
    // moment this fetch runs and replaces `recipes` outright.
    func loadFromCloudKit() async {
        guard let fetched = try? await CloudKitStore.shared.fetchRecipes() else { return }
        var merged = fetched
        let fetchedIDs = Set(fetched.map(\.id))
        merged.append(contentsOf: recipes.filter { !fetchedIDs.contains($0.id) })
        recipes = merged
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(recipes) else { return }
        try? data.write(to: storageURL)
    }

    private static func load(from url: URL) -> [Recipe] {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Recipe].self, from: data) else { return [] }
        return decoded
    }
}
