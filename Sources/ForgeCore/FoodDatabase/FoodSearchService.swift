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
    /// Feature request — "make searching for food items even more robust." FatSecret gets its own,
    /// shorter budget: a cold Render instance takes 30-60s to wake, which always blows past even an
    /// 8s cap and contributes nothing regardless — waiting the full `sourceTimeout` for it bought
    /// nothing but latency. Shorter here means a cold FatSecret gives up sooner without changing
    /// USDA/Open Food Facts' own budget at all.
    private let fatSecretTimeout: Duration
    /// Session-scoped query cache — retyping (or backspacing back to) an already-searched term
    /// returns instantly instead of re-hitting all 3 network sources from scratch. Keyed by the
    /// same normalized form used for ranking, so casing/whitespace differences still hit the cache.
    private var cache: [String: [FoodSearchResult]] = [:]

    public init(credentials: FoodDatabaseCredentials, countryFilter: String? = nil, session: URLSession = .shared, sourceTimeout: Duration = .seconds(8), fatSecretTimeout: Duration = .seconds(4)) {
        self.usda = USDAFoodDataClient(apiKey: credentials.usdaAPIKey, session: session)
        self.openFoodFacts = OpenFoodFactsClient(session: session)
        self.fatSecret = credentials.hasFatSecretProxyConfig
            ? FatSecretClient(proxyBaseURL: credentials.fatSecretProxyBaseURL!, proxySharedSecret: credentials.fatSecretProxySharedSecret!, session: session)
            : nil
        self.countryFilter = countryFilter
        self.sourceTimeout = sourceTimeout
        self.fatSecretTimeout = fatSecretTimeout
    }

    public func search(query: String) async -> [FoodSearchResult] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalizedQuery.isEmpty else { return [] }
        if let cached = cache[normalizedQuery] { return cached }

        async let usdaResults = Self.withTimeout(sourceTimeout) { try await self.usda.search(query: query) }
        async let offResults = Self.withTimeout(sourceTimeout) { try await self.openFoodFacts.search(query: query, countryFilter: self.countryFilter) }
        async let fatSecretResults: [FoodSearchResult]? = {
            guard let fatSecret else { return nil }
            return await Self.withTimeout(fatSecretTimeout) { try await fatSecret.search(query: query) }
        }()

        let usda = (await usdaResults) ?? []
        let off = (await offResults) ?? []
        let fs = (await fatSecretResults) ?? []
        // "Add to my food database" — a local, zero-latency, developer-curated source (see
        // `CuratedFoodLibrary`). Checked first: the dedup below keeps whichever copy of a given
        // food it sees first, so a curated entry wins over a same-named live-API result — the
        // point of curating it in the first place.
        let curated = CuratedFoodLibrary.search(normalizedQuery)

        // Merge/dedup priority (first copy of a given name+brand wins): curated, then FatSecret,
        // then Open Food Facts, then USDA last.
        //
        // "Let's try to move away from the USDA database" — USDA is demoted to a gap-filler rather
        // than removed, because it's the only *always-available* generic-food source: FatSecret
        // rides a free-tier proxy that sleeps after ~15min idle and takes 30-60s to wake against a
        // 4s timeout, so the first search after a quiet spell gets nothing from it. USDA covers
        // exactly that window. Where both do answer, FatSecret's naming is markedly better for a
        // consumer app — live comparison on "white rice": FatSecret returns plain "White Rice",
        // USDA returns "Beans and white rice" / "Rice, white, cooked, glutinous" — hence FatSecret
        // winning the dedup, and the explicit source penalty in `rankScore`.
        var combined = curated + fs + off + usda
        // Bug fix — "kiwi had 0 calories... get rid of any inaccurate foods that list 0 calories
        // when it should have some calories in them." Root cause: USDA/Open Food Facts both
        // include a record as long as it has *some* macro data (protein or energy present), but
        // then default a genuinely *missing* energy value to 0 via `?? 0` — so a real record that
        // lists protein/fat/carb but no energy value silently becomes a phantom "0 kcal" food
        // instead of being excluded. Filtering here (once, after merging all sources) catches it
        // regardless of which source it came from, rather than patching each client separately.
        combined = combined.filter { $0.kcal > 0 }
        var seen = Set<String>()
        combined = combined.filter { seen.insert("\($0.name.lowercased())|\($0.brand?.lowercased() ?? "")").inserted }

        // Re-rank so a plain search like "chicken breast" surfaces the generic, non-branded
        // nutrition entry first — branded products only outrank it when the query itself names
        // that brand (e.g. "quest bar"). Source order above is just the merge/dedup priority;
        // this is the actual display order.
        let indexed = combined.enumerated().map { (offset: $0.offset, result: $0.element) }
        let ranked = indexed.sorted { lhs, rhs in
            let lScore = Self.rankScore(for: lhs.result, query: normalizedQuery)
            let rScore = Self.rankScore(for: rhs.result, query: normalizedQuery)
            if lScore != rScore { return lScore > rScore }
            return lhs.offset < rhs.offset
        }
        let results = ranked.map(\.result)
        cache[normalizedQuery] = results
        return results
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

        // "Move away from the USDA database" — a penalty rather than removal, so USDA only ever
        // surfaces where nothing better answered (notably a cold FatSecret proxy). Sized at 10 so
        // it reorders sources within the same tier without overriding the two signals that matter
        // more: an exact name match (50) and the brand/generic distinction (100/200). A USDA
        // exact match still beats a merely-contains match from a preferred source.
        if result.source == .usda { score -= 10 }

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
