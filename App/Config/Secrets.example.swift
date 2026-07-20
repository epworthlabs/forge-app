import ForgeCore

/// Copy this file to `Secrets.swift` (gitignored — never commit real keys) and fill in your own.
///
/// USDA FDC: https://fdc.nal.usda.gov/api-key-signup — instant, free. DEMO_KEY works out of the
/// box for development at a lower rate limit; swap in a real key before relying on it daily.
///
/// FatSecret: the app never talks to FatSecret directly or holds its Client ID/Secret — those
/// live only in Forge/FoodProxy's environment (see that folder's README for deploy steps).
/// Register an app at https://platform.fatsecret.com, enable Canada (or your target market)
/// explicitly, deploy the proxy, then fill in fatSecretProxyBaseURL and
/// fatSecretProxySharedSecret below. Leave both nil to skip FatSecret entirely; FoodSearchService
/// degrades gracefully without it (Open Food Facts + USDA still work).
enum Secrets {
    static let usdaAPIKey = "DEMO_KEY"
    static let fatSecretProxyBaseURL: String? = nil
    static let fatSecretProxySharedSecret: String? = nil

    /// Open Food Facts has no locale awareness by default — unscoped search skews heavily
    /// French/European. Set to the target market's OFF country tag (e.g. "canada", "united-states");
    /// nil searches globally. See OpenFoodFactsClient.search doc comment for what this fixes.
    static let foodDatabaseCountryFilter: String? = "canada"

    /// PostHog Project API Key (client-side, safe to embed — not the admin Personal API Key).
    /// nil skips analytics setup entirely.
    static let postHogAPIKey: String? = nil
    static let postHogHost = "https://us.i.posthog.com"

    static var foodDatabaseCredentials: FoodDatabaseCredentials {
        FoodDatabaseCredentials(usdaAPIKey: usdaAPIKey, fatSecretProxyBaseURL: fatSecretProxyBaseURL, fatSecretProxySharedSecret: fatSecretProxySharedSecret)
    }
}
