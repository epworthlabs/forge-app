import Foundation

public enum FoodSource: String, Sendable, Equatable, Codable {
    case usda, openFoodFacts, fatSecret
}

// Feature request — favorites need to persist across launches (see AppStore.favoriteFoods,
// UserDefaults-backed); Codable lets that be a plain JSON blob rather than a new CloudKit schema.
public struct FoodSearchResult: Identifiable, Sendable, Equatable, Codable {
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

public extension FoodSearchResult {
    /// Best-effort grams the reported macros are "per" — parsed from `servingDescription` (e.g.
    /// "per 100g" → 100, "per 284g serving" → 284, "per 8oz serving" → ~227). nil when no gram or
    /// ounce figure could be found, so the caller can fall back to a servings-based multiplier
    /// instead of offering a grams/ounces entry it can't actually scale correctly.
    var referenceGrams: Double? {
        if let grams = Self.firstMatch(pattern: #"(?<![a-zA-Z])(\d+(?:\.\d+)?)\s*g\b"#, in: servingDescription) {
            return grams
        }
        if let ounces = Self.firstMatch(pattern: #"(?<![a-zA-Z])(\d+(?:\.\d+)?)\s*oz\b"#, in: servingDescription) {
            return ounces * 28.3495
        }
        return nil
    }

    private static func firstMatch(pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[r])
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
