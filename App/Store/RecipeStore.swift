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
    // Bug fix — "when I open my recipes I want to be able to edit them and see the quantities in
    // which I logged each ingredient, whether I logged it in grams, servings, etc." Reproduces
    // `FoodEntry`'s quantity/unit/referenceGrams + base-macro pattern: `kcal`/`proteinG`/`carbG`/
    // `fatG` above stay the already-scaled amount (what `Recipe.totalKcal` etc. sum), these are the
    // per-1-unit base the portion was scaled from, so a saved ingredient's quantity can be
    // redisplayed and re-edited later instead of being an opaque scaled snapshot. All defaulted so
    // recipes saved before this existed still decode fine — see `effectiveBase*` below.
    var quantity: Double = 1
    var unit: PortionUnit = .servings
    var referenceGrams: Double? = nil
    var baseKcal: Double? = nil
    var baseProteinG: Double? = nil
    var baseCarbG: Double? = nil
    var baseFatG: Double? = nil
}

extension RecipeIngredient {
    var effectiveBaseKcal: Double { baseKcal ?? Double(kcal) }
    var effectiveBaseProteinG: Double { baseProteinG ?? proteinG }
    var effectiveBaseCarbG: Double { baseCarbG ?? carbG }
    var effectiveBaseFatG: Double { baseFatG ?? fatG }

    /// "150 g", "1.5 servings", "3 oz" — how much of this ingredient went into the recipe, in
    /// whichever unit it was originally logged in. A pre-existing ingredient with no recorded
    /// quantity (saved before this field existed) reads as "1 serving," same fallback shape as
    /// `FoodEntry.effectiveBase*`.
    var quantityDescription: String {
        "\(WeightUnit.trimmedDecimal(quantity)) \(unit.rawValue)"
    }
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

    // FRG-383 — the whole library syncs as one blob (see CloudKitStore.saveRecipes); a delete is
    // just the next save without the recipe, so both paths push the same snapshot.
    func add(_ recipe: Recipe) {
        recipes.append(recipe)
        persist()
        let snapshot = recipes
        Task { await SyncQueue.shared.enqueue(.recipes(snapshot)) }
    }

    func remove(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        persist()
        let snapshot = recipes
        Task { await SyncQueue.shared.enqueue(.recipes(snapshot)) }
    }

    // Bug fix — "when I open my recipes I want to be able to edit them." In-place replace by id
    // rather than remove+add, so a recipe's position in the list doesn't jump to the end on edit.
    func update(_ recipe: Recipe) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[idx] = recipe
        persist()
        let snapshot = recipes
        Task { await SyncQueue.shared.enqueue(.recipes(snapshot)) }
    }

    // App Store Guideline 5.1.1(v) — account deletion. Local-only, no CloudKit push: the server
    // record is deleted directly by `CloudKitStore.deleteAllData`, and pushing an empty-list save
    // here would race it pointlessly.
    func clearAll() {
        recipes = []
        persist()
    }

    // Bug fix — "I want the recipe to show the ingredients it contains when I click them as logged
    // items." A logged `FoodEntry` only remembers the `FoodSearchResult.id` it came from
    // (`FoodEntry.sourceFoodID`); `Recipe.asFoodSearchResult` mints that id as `"recipe-<uuid>"`, so
    // this reverses the lookup back to the recipe that produced it.
    func recipe(forFoodID foodID: String) -> Recipe? {
        recipes.first { "recipe-\($0.id.uuidString)" == foodID }
    }

    // Bug fix — backfills recipes for a returning user (or a fresh reinstall) from CloudKit.
    // Called once after sign-in, same "called once after construction, not from init" reasoning
    // as `AppStore.loadHistoryFromCloudKit`. Merges rather than overwrites: a recipe added while
    // offline (queued in SyncQueue, not yet actually saved to CloudKit) would otherwise vanish the
    // moment this fetch runs and replaces `recipes` outright. If the merge found local-only
    // recipes the server doesn't have, push the union back up so the server heals too.
    func loadFromCloudKit() async {
        guard let fetched = try? await CloudKitStore.shared.fetchRecipes() else {
            print("[CloudKit] recipes fetch failed")
            return
        }
        let fetchedIDs = Set(fetched.map(\.id))
        let localOnly = recipes.filter { !fetchedIDs.contains($0.id) }
        recipes = fetched + localOnly
        persist()
        if !localOnly.isEmpty {
            let snapshot = recipes
            Task { await SyncQueue.shared.enqueue(.recipes(snapshot)) }
        }
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
