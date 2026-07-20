import Foundation

/// Queries all configured sources concurrently and merges results. Any single source failing
/// (bad key, network error, rate limit) degrades that source to an empty result rather than
/// failing the whole search — matches the PRD's fallback-chain intent for food lookup.
public actor FoodSearchService {
    private let usda: USDAFoodDataClient
    private let openFoodFacts: OpenFoodFactsClient
    private let fatSecret: FatSecretClient?
    /// Open Food Facts has no locale awareness by default and skews heavily European in an
    /// unscoped search — see OpenFoodFactsClient.search doc comment. nil means unscoped/global.
    private let countryFilter: String?

    public init(credentials: FoodDatabaseCredentials, countryFilter: String? = nil, session: URLSession = .shared) {
        self.usda = USDAFoodDataClient(apiKey: credentials.usdaAPIKey, session: session)
        self.openFoodFacts = OpenFoodFactsClient(session: session)
        self.fatSecret = credentials.hasFatSecretProxyConfig
            ? FatSecretClient(proxyBaseURL: credentials.fatSecretProxyBaseURL!, proxySharedSecret: credentials.fatSecretProxySharedSecret!, session: session)
            : nil
        self.countryFilter = countryFilter
    }

    public func search(query: String) async -> [FoodSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        async let usdaResults = try? usda.search(query: query)
        async let offResults = try? openFoodFacts.search(query: query, countryFilter: countryFilter)
        async let fatSecretResults = fatSecret?.search(query: query)

        let usda = (await usdaResults) ?? []
        let off = (await offResults) ?? []
        let fs = (try? await fatSecretResults) ?? []

        // Open Food Facts first: best barcode/packaged-food coverage, most likely to match what a
        // user actually scans or searches for day to day. USDA next for generic/whole foods.
        // FatSecret last as the paid-tier fallback for search gaps (PRD food-database decision).
        var combined = off + usda + fs
        var seen = Set<String>()
        combined = combined.filter { seen.insert("\($0.name.lowercased())|\($0.brand?.lowercased() ?? "")").inserted }
        return combined
    }

    /// Barcode lookup chain: Open Food Facts → FatSecret → nil (caller shows "not found, add
    /// manually"). USDA FDC is intentionally not in this chain — its UPC coverage is sparse and
    /// it's not built for barcode-first lookup the way the other two are.
    public func lookupBarcode(_ barcode: String) async -> FoodSearchResult? {
        // `try?` flattens the throwing-optional return here (Swift 5+), so one unwrap is enough.
        if let result = try? await openFoodFacts.lookupBarcode(barcode) {
            return result
        }
        // FatSecret's barcode support requires a separate food.find_id_for_barcode call before
        // foods.get — not implemented here; falls through to manual entry until that's built.
        return nil
    }
}
