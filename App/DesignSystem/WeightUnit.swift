import Foundation

/// Workout weights are stored in kg internally (ForgeCore's load-score/progressive-overload math
/// and the CloudKit schema are all kg-based already), but display/input defaults to lb — this is
/// purely a UI-layer conversion, not a storage or engine change.
enum WeightUnit {
    static let kgPerLb = 0.45359237

    static func lb(fromKg kg: Double) -> Double { kg / kgPerLb }
    static func kg(fromLb lb: Double) -> Double { lb * kgPerLb }
    static func roundedLb(fromKg kg: Double) -> Int { Int(lb(fromKg: kg).rounded()) }
}
