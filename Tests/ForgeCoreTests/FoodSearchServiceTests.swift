import Testing
import Foundation
@testable import ForgeCore

// Fixtures below are trimmed captures of real live responses (Jul 2026), not hand-guessed shapes —
// see USDAFoodDataClient/OpenFoodFactsClient doc comments for how they were verified.

// swiftlint:disable line_length
private let usdaFixture = Data("""
{
  "foods": [
    {
      "fdcId": 2187885,
      "description": "CHICKEN BREAST",
      "brandName": "GIANT EAGLE",
      "servingSize": 284.0,
      "servingSizeUnit": "g",
      "foodNutrients": [
        {"nutrientId": 1003, "value": 20.4},
        {"nutrientId": 1004, "value": 8.1},
        {"nutrientId": 1005, "value": 1.06},
        {"nutrientId": 1008, "value": 165}
      ]
    },
    {
      "fdcId": 999999,
      "description": "Lunchmeat, chicken breast, sliced",
      "foodNutrients": [
        {"nutrientId": 1007, "value": 3.47},
        {"nutrientId": 1180, "value": 35.3}
      ]
    }
  ]
}
""".utf8)

private let openFoodFactsFixture = Data("""
{
  "products": [
    {
      "product_name": "Nutella",
      "brands": "Ferrero, Nutella",
      "code": "3017620422003",
      "nutriments": {
        "proteins_100g": 6.3,
        "fat_100g": 30.9,
        "carbohydrates_100g": 57.5,
        "energy-kcal_100g": 539,
        "energy-kcal_unit": "kcal"
      }
    },
    {
      "product_name": "",
      "code": "0000000000000",
      "nutriments": {}
    }
  ]
}
""".utf8)

private let openFoodFactsBarcodeFixture = Data("""
{
  "status": 1,
  "product": {
    "product_name": "Nutella",
    "brands": "Ferrero, Nutella",
    "code": "3017620422003",
    "nutriments": {
      "proteins_100g": 6.3,
      "fat_100g": 30.9,
      "carbohydrates_100g": 57.5,
      "energy-kcal_100g": 539
    }
  }
}
""".utf8)

private let openFoodFactsNotFoundFixture = Data(#"{"status": 0}"#.utf8)

private let fatSecretFixture = Data("""
{
  "foods": {
    "food": [
      {
        "food_id": "1",
        "food_name": "Chicken Breast",
        "food_description": "Per 100g - Calories: 165kcal | Fat: 3.57g | Carbs: 0.00g | Protein: 31.02g"
      },
      {
        "food_id": "2",
        "food_name": "Mystery Item With Unparseable Description",
        "food_description": "Serving info unavailable"
      }
    ]
  }
}
""".utf8)
// swiftlint:enable line_length

private extension [FoodSearchResult] {
    /// `FoodSearchService.search` merges live API results with locally-bundled ones
    /// (`CuratedFoodLibrary`, and per-device custom foods/recipes) that no `MockURLProtocol` stub
    /// controls — searching "chicken" picks up the curated chicken entries for real. The tests
    /// below are about the *network* merge/dedup/timeout behaviour specifically, so they filter
    /// to network-sourced results rather than asserting a total count, which would otherwise
    /// break every time someone adds a matching food to `Resources/foods.json`.
    var fromNetworkSources: [FoodSearchResult] {
        filter { $0.source == .usda || $0.source == .openFoodFacts || $0.source == .fatSecret }
    }
}

@Suite struct FatSecretClientTests {
    @Test func parsesMacrosFromFreeTextDescription() {
        let description = "Per 100g - Calories: 165kcal | Fat: 3.57g | Carbs: 0.00g | Protein: 31.02g"
        let macros = FatSecretClient.parseMacros(from: description)

        #expect(macros.kcal == 165)
        #expect(macros.fat == 3.57)
        #expect(macros.carb == 0.00)
        #expect(macros.protein == 31.02)
    }
}

// Everything below shares MockURLProtocol's single static stub dictionary and real URL fragments
// ("search.pl", "api.nal.usda.gov", "api/v2/product") — Swift Testing parallelizes across suites
// by default, so without forcing all of this onto one serialized suite, two tests stubbing the
// same fragment concurrently race and clobber each other's expected response. That's a real
// intermittent failure this produced during development, not a hypothetical.
@Suite(.serialized) struct FoodDatabaseNetworkTests {
    @Test func usdaDecodesRealResponseShapeAndFiltersFoodsMissingMacros() async throws {
        MockURLProtocol.stub(urlContains: "api.nal.usda.gov", data: usdaFixture)
        let client = USDAFoodDataClient(apiKey: "DEMO_KEY", session: MockURLProtocol.makeSession())

        let results = try await client.search(query: "chicken breast")

        // The lunchmeat entry has no protein/fat/carb/energy nutrients — regression coverage for
        // a real USDA record found during development that had 71 nutrients and none of the big four.
        #expect(results.count == 1)
        #expect(results[0].kcal == 165)
        #expect(results[0].proteinG == 20.4)
        #expect(results[0].fatG == 8.1)
        #expect(results[0].carbG == 1.06)
        #expect(results[0].servingDescription == "per 284g serving")
        #expect(results[0].source == .usda)
    }

    // Feature request — "it only recommends branded foods, I want generic food with no labels at
    // the top." Confirmed live against the real API that an unscoped search returns mostly
    // `dataType: "Branded"` matches, crowding out the actual generic entry. Regression coverage for
    // the fix: the outgoing request must actually scope to USDA's generic/reference datasets.
    @Test func usdaSearchScopesToGenericDataTypesOnly() async throws {
        MockURLProtocol.stub(urlContains: "api.nal.usda.gov", data: usdaFixture)
        let client = USDAFoodDataClient(apiKey: "DEMO_KEY", session: MockURLProtocol.makeSession())

        _ = try await client.search(query: "chicken breast")

        let requestedURL = MockURLProtocol.lastRequestURL?.absoluteString ?? ""
        #expect(requestedURL.contains("dataType"))
        #expect(requestedURL.contains("Foundation"))
        #expect(requestedURL.contains("SR%20Legacy") || requestedURL.contains("SR Legacy"))
        #expect(!requestedURL.contains("Branded"))
        // Regression — requesting `Survey (FNDDS)` made USDA's edge layer intermittently reject
        // the whole request with a bare nginx 400 (measured 1/8 success alone, 4/8 combined), which
        // the service's per-source `try?` swallowed as an empty result. A mocked session can't
        // reproduce a real 400, so this asserts the actual trigger instead: no parentheses in any
        // outgoing USDA query parameter.
        #expect(!requestedURL.contains("FNDDS"))
        #expect(!requestedURL.contains("(") && !requestedURL.contains("%28"))
    }

    @Test func openFoodFactsDecodesMixedTypeNutrimentsDictionaryWithoutCrashing() async throws {
        MockURLProtocol.stub(urlContains: "search.pl", data: openFoodFactsFixture)
        let client = OpenFoodFactsClient(session: MockURLProtocol.makeSession())

        let results = try await client.search(query: "nutella")

        // Second product has an empty name and no nutrients — should be filtered, not crash the
        // whole decode (the real API mixes numeric and string values in the same dict, which is
        // why nutriments needs the lenient decoder rather than a plain [String: Double]).
        #expect(results.count == 1)
        #expect(results[0].name == "Nutella")
        #expect(results[0].kcal == 539)
        #expect(results[0].source == .openFoodFacts)
    }

    @Test func openFoodFactsBarcodeLookupReturnsProductWhenFound() async throws {
        MockURLProtocol.stub(urlContains: "api/v2/product", data: openFoodFactsBarcodeFixture)
        let client = OpenFoodFactsClient(session: MockURLProtocol.makeSession())

        let result = try await client.lookupBarcode("3017620422003")
        #expect(result?.name == "Nutella")
        #expect(result?.barcodeUPC == "3017620422003")
    }

    @Test func openFoodFactsBarcodeLookupReturnsNilWhenNotFound() async throws {
        MockURLProtocol.stub(urlContains: "api/v2/product", data: openFoodFactsNotFoundFixture)
        let client = OpenFoodFactsClient(session: MockURLProtocol.makeSession())

        let result = try await client.lookupBarcode("0000000000000")
        #expect(result == nil)
    }

    // Feature request — "I feel like I'm getting a lot of low quality results." Same defensive
    // guard USDA/Open Food Facts already apply: a description that fails to parse into any macros
    // (unexpected format, truncated text) shouldn't surface as a phantom 0-calorie food.
    @Test func fatSecretFiltersOutEntriesWithUnparseableDescriptions() async throws {
        MockURLProtocol.stub(urlContains: "fatsecret.test", data: fatSecretFixture)
        let client = FatSecretClient(proxyBaseURL: "https://fatsecret.test", proxySharedSecret: "x", session: MockURLProtocol.makeSession())

        let results = try await client.search(query: "chicken breast")

        #expect(results.count == 1)
        #expect(results[0].name == "Chicken Breast")
        #expect(results[0].kcal == 165)
    }

    @Test func serviceCombinesSourcesAndDedupesByNameAndBrand() async {
        MockURLProtocol.stub(urlContains: "api.nal.usda.gov", data: usdaFixture)
        MockURLProtocol.stub(urlContains: "search.pl", data: openFoodFactsFixture)
        let credentials = FoodDatabaseCredentials(usdaAPIKey: "DEMO_KEY")
        let service = FoodSearchService(credentials: credentials, session: MockURLProtocol.makeSession())

        let results = await service.search(query: "chicken").fromNetworkSources

        #expect(results.count == 2) // 1 valid USDA result + 1 valid Open Food Facts result
        #expect(results.contains { $0.source == .usda })
        #expect(results.contains { $0.source == .openFoodFacts })
    }

    // "Let's try to move away from the USDA database" — demoted, not removed: it still answers
    // when nothing better does (a cold FatSecret proxy), but never leads when a preferred source
    // returned a comparable match. Both fixtures here are unbranded and merely *contain* the
    // query, so source priority is the only thing separating them.
    @Test func usdaRanksBelowPreferredSourcesForComparableMatches() async {
        MockURLProtocol.stub(urlContains: "api.nal.usda.gov", data: usdaFixture)
        MockURLProtocol.stub(urlContains: "fatsecret.test", data: fatSecretFixture)
        let credentials = FoodDatabaseCredentials(
            usdaAPIKey: "DEMO_KEY",
            fatSecretProxyBaseURL: "https://fatsecret.test",
            fatSecretProxySharedSecret: "secret"
        )
        let service = FoodSearchService(credentials: credentials, session: MockURLProtocol.makeSession())

        let results = await service.search(query: "chicken").fromNetworkSources
        let usdaIndex = results.firstIndex { $0.source == .usda }
        let fatSecretIndex = results.firstIndex { $0.source == .fatSecret }

        #expect(usdaIndex != nil) // still present — a gap-filler, not removed
        #expect(fatSecretIndex != nil)
        if let usdaIndex, let fatSecretIndex { #expect(fatSecretIndex < usdaIndex) }
    }

    @Test func serviceEmptyQueryReturnsNoResultsWithoutNetworkCalls() async {
        let credentials = FoodDatabaseCredentials(usdaAPIKey: "DEMO_KEY")
        let service = FoodSearchService(credentials: credentials, session: MockURLProtocol.makeSession())

        let results = await service.search(query: "   ")
        #expect(results.isEmpty)
    }

    @Test func serviceMissingFatSecretCredentialsSkipsThatSourceGracefully() async {
        MockURLProtocol.stub(urlContains: "api.nal.usda.gov", data: usdaFixture)
        MockURLProtocol.stub(urlContains: "search.pl", data: openFoodFactsFixture)
        let credentials = FoodDatabaseCredentials(usdaAPIKey: "DEMO_KEY") // no FatSecret creds
        let service = FoodSearchService(credentials: credentials, session: MockURLProtocol.makeSession())

        let results = await service.search(query: "chicken").fromNetworkSources
        #expect(!results.contains { $0.source == .fatSecret })
        #expect(results.count == 2)
    }

    // Regression coverage — FatSecret's proxy (Render free tier) cold-starting after idle used to
    // block the *entire* search on it, even though USDA/Open Food Facts had already come back.
    // Uses a tiny injected timeout + a deliberately slower stubbed response so this doesn't
    // actually wait out a real-world 8s timeout.
    @Test func slowSourceTimesOutWithoutBlockingFasterSources() async throws {
        MockURLProtocol.stub(urlContains: "api.nal.usda.gov", data: usdaFixture)
        MockURLProtocol.stub(urlContains: "search.pl", data: openFoodFactsFixture)
        MockURLProtocol.stubDelayed(urlContains: "forge-food-proxy.test", data: usdaFixture, delay: 0.3)
        let credentials = FoodDatabaseCredentials(
            usdaAPIKey: "DEMO_KEY",
            fatSecretProxyBaseURL: "https://forge-food-proxy.test",
            fatSecretProxySharedSecret: "secret"
        )
        let service = FoodSearchService(
            credentials: credentials, session: MockURLProtocol.makeSession(),
            sourceTimeout: .milliseconds(50), fatSecretTimeout: .milliseconds(50)
        )

        let start = ContinuousClock.now
        let results = await service.search(query: "chicken").fromNetworkSources
        let elapsed = start.duration(to: .now)

        // The 0.3s delayed FatSecret response should get cut off by the 50ms timeout, not awaited
        // in full — total time stays close to the timeout, nowhere near the full delay.
        #expect(elapsed < .milliseconds(250))
        #expect(!results.contains { $0.source == .fatSecret })
        #expect(results.count == 2) // USDA + Open Food Facts still came back
    }

    // Feature request — "make searching for food items even more robust." Repeating (or
    // re-casing/re-whitespacing) an already-searched query should return instantly from the
    // in-memory cache rather than re-hitting every source from scratch.
    @Test func repeatedQueryHitsCacheNotNetwork() async throws {
        MockURLProtocol.stub(urlContains: "api.nal.usda.gov", data: usdaFixture)
        MockURLProtocol.stub(urlContains: "search.pl", data: openFoodFactsFixture)
        MockURLProtocol.resetRequestCounts()
        let credentials = FoodDatabaseCredentials(usdaAPIKey: "DEMO_KEY")
        let service = FoodSearchService(credentials: credentials, session: MockURLProtocol.makeSession())

        _ = await service.search(query: "chicken")
        let firstCount = MockURLProtocol.requestCounts["api.nal.usda.gov"] ?? 0
        _ = await service.search(query: "  Chicken  ") // same query, different case/whitespace
        let secondCount = MockURLProtocol.requestCounts["api.nal.usda.gov"] ?? 0

        #expect(firstCount == 1)
        #expect(secondCount == 1) // no second network hit — served from cache
    }
}
