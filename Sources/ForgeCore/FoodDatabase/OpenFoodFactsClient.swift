import Foundation

/// Open Food Facts — free, no API key, no request ceiling, strong global barcode/packaged-food
/// coverage. Public domain data under ODbL: attribution is required wherever results are shown
/// (see Settings/About in the app).
///
/// One real gotcha found while building this against the live API: OFF silently blocks requests
/// with a generic-looking User-Agent (returns an HTML bot-wall page instead of JSON) even though
/// nothing in their public docs errors loudly about it. A descriptive UA is required, not optional.
public struct OpenFoodFactsClient: Sendable {
    private let session: URLSession
    private let userAgent = "Forge-iOS/0.1 (contact@forge.app)"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private struct SearchResponse: Decodable {
        var products: [Product]
    }

    private struct ProductResponse: Decodable {
        var status: Int
        var product: Product?
    }

    private struct Product: Decodable {
        var product_name: String?
        var brands: String?
        var code: String?
        var nutriments: FlexibleNutriments?

        enum CodingKeys: String, CodingKey {
            case product_name, brands, code, nutriments
        }
    }

    private struct FlexibleNutriments: Decodable {
        // Open Food Facts' nutriments object mixes numbers and strings in the same dictionary
        // (e.g. "energy-kcal_unit": "kcal" next to "energy-kcal_100g": 539) — decode leniently
        // rather than failing the whole product on one non-numeric field.
        let values: [String: Double]
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode([String: JSONValue].self)
            values = raw.compactMapValues { $0.doubleValue }
        }
    }

    private enum JSONValue: Decodable {
        case double(Double), string(String), other
        var doubleValue: Double? { if case .double(let d) = self { return d }; return nil }
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { self = .double(d); return }
            if let s = try? c.decode(String.self) { self = .string(s); return }
            self = .other
        }
    }

    /// `countryFilter` matters more than it looks: Open Food Facts' search has no locale/region
    /// awareness by default, and its data skews heavily French/European (the project originated
    /// there). An English-language query like "chicken breast" returns mostly French-labeled
    /// products unless scoped — confirmed live, not assumed: unscoped, results were dominated by
    /// Fleury Michon/Herta/Hacendado; scoped to "canada", Kirkland/President's Choice/Costco.
    public func search(query: String, pageSize: Int = 15, countryFilter: String? = nil) async throws -> [FoodSearchResult] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "fields", value: "product_name,brands,code,nutriments"),
        ]
        if let countryFilter {
            components.queryItems?.append(contentsOf: [
                URLQueryItem(name: "tagtype_0", value: "countries"),
                URLQueryItem(name: "tag_contains_0", value: "contains"),
                URLQueryItem(name: "tag_0", value: countryFilter),
            ])
        }
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: request)
        let decoded = try decodeLenient(data, as: SearchResponse.self)
        return decoded.products.compactMap(mapProduct)
    }

    public func lookupBarcode(_ barcode: String) async throws -> FoodSearchResult? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: request)
        let decoded = try decodeLenient(data, as: ProductResponse.self)
        guard decoded.status == 1, let product = decoded.product else { return nil }
        return mapProduct(product)
    }

    private func decodeLenient<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    private func mapProduct(_ product: Product) -> FoodSearchResult? {
        guard let name = product.product_name, !name.isEmpty else { return nil }
        let n = product.nutriments?.values ?? [:]
        // Missing entirely (rather than genuinely zero) isn't useful to show as a log-able food.
        guard n["energy-kcal_100g"] != nil || n["proteins_100g"] != nil else { return nil }

        return FoodSearchResult(
            id: "off-\(product.code ?? UUID().uuidString)",
            name: name,
            brand: product.brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces),
            kcal: Int((n["energy-kcal_100g"] ?? 0).rounded()),
            proteinG: n["proteins_100g"] ?? 0,
            carbG: n["carbohydrates_100g"] ?? 0,
            fatG: n["fat_100g"] ?? 0,
            servingDescription: "per 100g",
            source: .openFoodFacts,
            barcodeUPC: product.code
        )
    }
}
