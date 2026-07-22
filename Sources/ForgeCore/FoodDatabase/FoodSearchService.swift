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
    /// FatSecret's proxy (FoodProxy/, Render free tier) spins down after ~15 minutes idle — a cold
    /// start can take 30-60s. Without a cap, one slow/cold source blocked the *entire* search that
    /// long even though USDA/Open Food Facts had already come back — this is what made lookups feel
    /// unresponsive. Overridable so tests don't have to actually wait out the timeout.
    private let sourceTimeout: Duration

    public init(credentials: FoodDatabaseCredentials, countryFilter: String? = nil, session: URLSession = .shared, sourceTimeout: Duration = .seconds(8)) {
        self.usda = USDAFoodDataClient(apiKey: credentials.usdaAPIKey, session: session)
        self.openFoodFacts = OpenFoodFactsClient(session: session)
        self.fatSecret = credentials.hasFatSecretProxyConfig
            ? FatSecretClient(proxyBaseURL: credentials.fatSecretProxyBaseURL!, proxySharedSecret: credentials.fatSecretProxySharedSecret!, session: session)
            : nil
        self.countryFilter = countryFilter
        self.sourceTimeout = sourceTimeout
    }

    public func search(query: String) async -> [FoodSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        async let usdaResults = Self.withTimeout(sourceTimeout) { try await self.usda.search(query: query) }
        async let offResults = Self.withTimeout(sourceTimeout) { try await self.openFoodFacts.search(query: query, countryFilter: self.countryFilter) }
        async let fatSecretResults: [FoodSearchResult]? = {
            guard let fatSecret else { return nil }
            return await Self.withTimeout(sourceTimeout) { try await fatSecret.search(query: query) }
        }()

        let usda = (await usdaResults) ?? []
        let off = (await offResults) ?? []
        let fs = (await fatSecretResults) ?? []

        // Open Food Facts first: best barcode/packaged-food coverage, most likely to match what a
        // user actually scans or searches for day to day. USDA next for generic/whole foods.
        // FatSecret last as the paid-tier fallback for search gaps (PRD food-database decision).
        var combined = off + usda + fs
        var seen = Set<String>()
        combined = combined.filter { seen.insert("\($0.name.lowercased())|\($0.brand?.lowercased() ?? "")").inserted }

        // Re-rank so a plain search like "chicken breast" surfaces the generic, non-branded
        // nutrition entry first — branded products only outrank it when the query itself names
        // that brand (e.g. "quest bar"). Source order above is just the merge/dedup priority;
        // this is the actual display order.
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        let indexed = combined.enumerated().map { (offset: $0.offset, result: $0.element) }
        let ranked = indexed.sorted { lhs, rhs in
            let lScore = Self.rankScore(for: lhs.result, query: normalizedQuery)
            let rScore = Self.rankScore(for: rhs.result, query: normalizedQuery)
            if lScore != rScore { return lScore > rScore }
            return lhs.offset < rhs.offset
        }
        return ranked.map(\.result)
    }

    private static func rankScore(for result: FoodSearchResult, query: String) -> Int {
        var score = 0
        let name = result.name.lowercased()
        let brand = result.brand?.lowercased()

        if let brand, !brand.isEmpty, query.contains(brand) || brand.contains(query) {
            // The user searched for this specific brand — that's the whole point of the query.
            score += 200
        } else if brand == nil || brand!.isEmpty {
            // Generic, non-branded nutrition — the "regular chicken breast" case.
            score += 100
        }

        if name == query {
            score += 50
        } else if name.hasPrefix(query) {
            score += 20
        } else if name.contains(query) {
            score += 5
        }

        return score
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

    /// Races `operation` against a timeout — whichever finishes first wins, and the loser is
    /// cancelled. `URLSession`'s `data(for:)` honors cooperative cancellation, so a timed-out
    /// request is actually aborted, not just ignored.
    private static func withTimeout<T: Sendable>(_ duration: Duration, operation: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await operation() }
            group.addTask {
                try? await Task.sleep(for: duration)
                return nil
            }
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
}
