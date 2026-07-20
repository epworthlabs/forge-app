import Foundation

/// FatSecret Platform API — free tier 150K req/month, per-market food databases (Canada included
/// if enabled at registration — see PRD). FatSecret's OAuth 2.0 requires requests to originate
/// from a fixed, allowlisted IP and recommends holding the Client ID/Secret server-side rather
/// than embedding them on individual devices (see their OAuth 2.0 guide) — a mobile app can't
/// satisfy either constraint directly, since each user's phone has a different, changing IP.
/// This client therefore never talks to FatSecret directly: it calls a small proxy server
/// (`Forge/FoodProxy`) that holds the real credentials and has a fixed outbound IP. Verified
/// against the live FatSecret API (via curl, using the exact request shapes this proxy forwards)
/// — OAuth token exchange succeeded; the search call was correctly formed but rejected by
/// FatSecret's IP allowlist from this machine's IP, which the proxy exists to solve.
public actor FatSecretClient {
    private let proxyBaseURL: String
    private let proxySharedSecret: String
    private let session: URLSession

    public init(proxyBaseURL: String, proxySharedSecret: String, session: URLSession = .shared) {
        self.proxyBaseURL = proxyBaseURL
        self.proxySharedSecret = proxySharedSecret
        self.session = session
    }

    private struct SearchResponse: Decodable {
        var foods: FoodsWrapper?
    }
    private struct FoodsWrapper: Decodable {
        var food: [Food]?
    }
    private struct Food: Decodable {
        var food_id: String
        var food_name: String
        var brand_name: String?
        var food_description: String
    }

    public func search(query: String, maxResults: Int = 10) async throws -> [FoodSearchResult] {
        var components = URLComponents(string: "\(proxyBaseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "max_results", value: String(maxResults)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(proxySharedSecret, forHTTPHeaderField: "X-App-Secret")

        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)

        return (decoded.foods?.food ?? []).map { food in
            // food_description is a single free-text summary like "Per 100g - Calories: 165kcal |
            // Fat: 3.57g | Carbs: 0.00g | Protein: 31.02g" — parsed rather than structured fields.
            let macros = Self.parseMacros(from: food.food_description)
            return FoodSearchResult(
                id: "fatsecret-\(food.food_id)",
                name: food.food_name,
                brand: food.brand_name,
                kcal: macros.kcal,
                proteinG: macros.protein,
                carbG: macros.carb,
                fatG: macros.fat,
                servingDescription: Self.servingDescription(from: food.food_description),
                source: .fatSecret
            )
        }
    }

    static func parseMacros(from description: String) -> (kcal: Int, protein: Double, carb: Double, fat: Double) {
        func extract(_ label: String) -> Double {
            guard let range = description.range(of: "\(label): ") else { return 0 }
            let rest = description[range.upperBound...]
            let numberString = rest.prefix(while: { $0.isNumber || $0 == "." })
            return Double(numberString) ?? 0
        }
        return (kcal: Int(extract("Calories")), protein: extract("Protein"), carb: extract("Carbs"), fat: extract("Fat"))
    }

    static func servingDescription(from description: String) -> String {
        String(description.prefix(while: { $0 != "-" })).trimmingCharacters(in: .whitespaces).isEmpty
            ? "per serving"
            : String(description.prefix(while: { $0 != "-" })).trimmingCharacters(in: .whitespaces)
    }
}
