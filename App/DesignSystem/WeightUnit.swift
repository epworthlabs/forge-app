import Foundation

/// Workout weights are stored in kg internally (ForgeCore's load-score/progressive-overload math
/// and the CloudKit schema are all kg-based already), but display/input defaults to lb — this is
/// purely a UI-layer conversion, not a storage or engine change.
enum WeightUnit {
    static let kgPerLb = 0.45359237

    static func lb(fromKg kg: Double) -> Double { kg / kgPerLb }
    static func kg(fromLb lb: Double) -> Double { lb * kgPerLb }
    static func roundedLb(fromKg kg: Double) -> Int { Int(lb(fromKg: kg).rounded()) }

    // Feature request — "when weights are first listed by default... always defaulted to
    // increments of 5. I don't want to see 121lbs." Rounds to the nearest 5lb but returns kg (the
    // storage unit), so the seeded value itself is clean — not just a display-layer patch that'd
    // still leave 121lb-style numbers sitting in `targetWeightKg`.
    static func roundedToNearestFiveLb(fromKg kg: Double) -> Double {
        let nearestFive = (lb(fromKg: kg) / 5).rounded() * 5
        return Self.kg(fromLb: nearestFive)
    }

    // Feature request — "need to be able to input decimals into weights" (plate math like
    // 62.5/135.5 lb). Trims to a clean decimal instead of always collapsing to a whole number —
    // shared with `PortionConfirmSheet`'s identical food-quantity formatting so the two don't
    // drift apart.
    static func trimmedDecimal(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
