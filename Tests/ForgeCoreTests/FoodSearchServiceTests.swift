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
// swiftlint:enable line_length

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

    @Test func serviceCombinesSourcesAndDedupesByNameAndBrand() async {
        MockURLProtocol.stub(urlContains: "api.nal.usda.gov", data: usdaFixture)
        MockURLProtocol.stub(urlContains: "search.pl", data: openFoodFactsFixture)
        let credentials = FoodDatabaseCredentials(usdaAPIKey: "DEMO_KEY")
        let service = FoodSearchService(credentials: credentials, session: MockURLProtocol.makeSession())

        let results = await service.search(query: "chicken")

        #expect(results.count == 2) // 1 valid USDA result + 1 valid Open Food Facts result
        #expect(results.contains { $0.source == .usda })
        #expect(results.contains { $0.source == .openFoodFacts })
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

        let results = await service.search(query: "chicken")
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
            credentials: credentials, session: MockURLProtocol.makeSession(), sourceTimeout: .milliseconds(50)
        )

        let start = ContinuousClock.now
        let results = await service.search(query: "chicken")
        let elapsed = start.duration(to: .now)

        // The 0.3s delayed FatSecret response should get cut off by the 50ms timeout, not awaited
        // in full — total time stays close to the timeout, nowhere near the full delay.
        #expect(elapsed < .milliseconds(250))
        #expect(!results.contains { $0.source == .fatSecret })
        #expect(results.count == 2) // USDA + Open Food Facts still came back
    }
}
