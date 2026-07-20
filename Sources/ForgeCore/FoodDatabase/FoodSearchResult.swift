import Foundation

public enum FoodSource: String, Sendable, Equatable {
    case usda, openFoodFacts, fatSecret
}

public struct FoodSearchResult: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var brand: String?
    public var kcal: Int
    public var proteinG: Double
    public var carbG: Double
    public var fatG: Double
    /// e.g. "per 284g serving" (USDA branded) or "per 100g" (Open Food Facts) — the two sources
    /// don't normalize to the same base, so this stays visible rather than implying false precision.
    public var servingDescription: String
    public var source: FoodSource
    public var barcodeUPC: String?

    public init(id: String, name: String, brand: String? = nil, kcal: Int, proteinG: Double, carbG: Double,
                fatG: Double, servingDescription: String, source: FoodSource, barcodeUPC: String? = nil) {
        self.id = id
        self.name = name
        self.brand = brand
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbG = carbG
        self.fatG = fatG
        self.servingDescription = servingDescription
        self.source = source
        self.barcodeUPC = barcodeUPC
    }
}

/// Injected by the app layer (from Secrets, gitignored) — never hardcoded here. FatSecret's real
/// Client ID/Secret never appear here or anywhere in the app; they live only in the FoodProxy
/// server's environment. The app just needs the proxy's URL and the shared secret that gates it.
public struct FoodDatabaseCredentials: Sendable {
    public var usdaAPIKey: String
    public var fatSecretProxyBaseURL: String?
    public var fatSecretProxySharedSecret: String?

    public init(usdaAPIKey: String = "DEMO_KEY", fatSecretProxyBaseURL: String? = nil, fatSecretProxySharedSecret: String? = nil) {
        self.usdaAPIKey = usdaAPIKey
        self.fatSecretProxyBaseURL = fatSecretProxyBaseURL
        self.fatSecretProxySharedSecret = fatSecretProxySharedSecret
    }

    var hasFatSecretProxyConfig: Bool {
        guard let url = fatSecretProxyBaseURL, let secret = fatSecretProxySharedSecret else { return false }
        return !url.isEmpty && !secret.isEmpty
    }
}
