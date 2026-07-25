import Foundation

/// "I want to add to my food database, is there a way to do that?" — there was no first-party
/// food database before this; search only ever hit live USDA/Open Food Facts/FatSecret APIs (see
/// `FoodSearchService`), so there was nothing the developer directly controlled the quality of.
/// This mirrors `ExerciseLibrary` (`Exercise.swift`) exactly: a bundled JSON file, loaded once,
/// extended by hand-editing `Resources/foods.json` and shipping a build — no admin UI, same
/// workflow as the 873-exercise library already uses.
public enum CuratedFoodLibrary {
    /// Deliberately a smaller schema than `FoodSearchResult` itself (no `brand`/`source`/`barcodeUPC`)
    /// — those don't apply to a hand-authored entry, and keeping the JSON minimal makes it easier
    /// to add to by hand.
    private struct Entry: Decodable {
        var id: String
        var name: String
        var kcal: Int
        var proteinG: Double
        var carbG: Double
        var fatG: Double
        var servingDescription: String
    }

    public static let all: [FoodSearchResult] = {
        guard let url = Bundle.module.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.map {
            FoodSearchResult(
                id: $0.id, name: $0.name, kcal: $0.kcal, proteinG: $0.proteinG, carbG: $0.carbG, fatG: $0.fatG,
                servingDescription: $0.servingDescription, source: .curated
            )
        }
    }()

    public static func search(_ query: String) -> [FoodSearchResult] {
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) }
    }
}
