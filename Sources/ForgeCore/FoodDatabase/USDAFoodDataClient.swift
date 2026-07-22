import Foundation

/// USDA FoodData Central — generic/whole foods, scoped away from its own "Branded" dataset (see
/// `search`'s `dataType` filter below). Free, 1,000 req/hr per key. Response shape confirmed
/// against the live API (Jul 2026), not guessed: nutrients come back as a flat array keyed by
/// nutrientId, not a fixed macros object, and individual foods can genuinely omit the big four
/// (seen on a "Foundation" dataType record) — this decodes defensively rather than assuming every
/// result has complete data.
public struct USDAFoodDataClient: Sendable {
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private struct SearchResponse: Decodable {
        var foods: [Food]
    }

    private struct Food: Decodable {
        var fdcId: Int
        var description: String
        var brandName: String?
        var servingSize: Double?
        var servingSizeUnit: String?
        var foodNutrients: [Nutrient]
    }

    private struct Nutrient: Decodable {
        var nutrientId: Int
        var value: Double?
    }

    // Standard USDA "nutrient number" IDs — confirmed against a live Branded-food response.
    private enum NutrientID {
        static let protein = 1003
        static let fat = 1004
        static let carbohydrate = 1005
        static let energy = 1008
    }

    // Feature request — "it only recommends branded foods, I want it to include generic food with
    // no labels at the top." Root cause, confirmed against the live API: an unscoped search for
    // "chicken breast" returned 10 of its top 15 hits as `dataType: "Branded"` — the actual plain
    // "Chicken, breast, boneless, skinless, raw" entry didn't even make the first page, crowded out
    // by supermarket house-brand products. `FoodSearchService`'s ranking already scores unbranded
    // results higher, but it can only re-rank what actually comes back — with Branded dominating
    // USDA's own top-N, there was rarely a generic candidate to promote. Scoping to just
    // Foundation/SR Legacy/Survey (FNDDS) — USDA's actual generic/reference-food datasets — drops
    // Branded from USDA's results entirely; Open Food Facts and FatSecret already cover branded
    // products on their own, so nothing is lost, and USDA now does exactly what the source-priority
    // comment in `FoodSearchService.search` already claimed it did ("USDA next for generic/whole
    // foods"). Confirmed live: the same query scoped this way returns 15/15 unbranded matches,
    // including the plain "Chicken, breast, boneless, skinless, raw" entry.
    public func search(query: String, pageSize: Int = 15) async throws -> [FoodSearchResult] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey (FNDDS)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)

        return decoded.foods.compactMap { food in
            func value(_ id: Int) -> Double? {
                food.foodNutrients.first(where: { $0.nutrientId == id })?.value
            }
            // A food with none of the big four isn't useful to show in a nutrition log — skip it
            // rather than displaying misleading zeros (this happens for real, seen live on a
            // Foundation-type record with 71 micronutrients and no macro summary).
            guard value(NutrientID.energy) != nil || value(NutrientID.protein) != nil else { return nil }

            let serving: String
            if let size = food.servingSize, let unit = food.servingSizeUnit {
                serving = "per \(Int(size))\(unit) serving"
            } else {
                serving = "per 100g"
            }

            return FoodSearchResult(
                id: "usda-\(food.fdcId)",
                name: food.description.capitalized,
                brand: food.brandName,
                kcal: Int((value(NutrientID.energy) ?? 0).rounded()),
                proteinG: value(NutrientID.protein) ?? 0,
                carbG: value(NutrientID.carbohydrate) ?? 0,
                fatG: value(NutrientID.fat) ?? 0,
                servingDescription: serving,
                source: .usda
            )
        }
    }
}
