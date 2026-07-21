import Foundation

public enum Sex: String, Sendable, Codable {
    case male, female
}

public enum ActivityLevel: Double, Sendable, Codable {
    case low = 1.2
    case moderate = 1.375
    case high = 1.55

    var multiplier: Double { rawValue }
}

public enum Goal: String, Sendable, Codable {
    case cut, bulk, maintain, recomp

    /// Midpoint of the PRD's researched adjustment ranges (cut −15–25%, bulk +10–15%).
    var tdeeAdjustment: Double {
        switch self {
        case .cut: return -0.20
        case .bulk: return 0.125
        case .maintain, .recomp: return 0.0
        }
    }

    /// g/kg bodyweight, PRD Appendix step 4 — held stable regardless of Load Score.
    var proteinPerKg: Double {
        switch self {
        case .cut: return 2.4
        case .bulk, .maintain, .recomp: return 1.7
        }
    }
}

public struct UserProfile: Sendable, Codable {
    public var weightKg: Double
    public var heightCm: Double
    public var age: Int
    public var sex: Sex
    public var activityLevel: ActivityLevel
    public var goal: Goal
    /// Fat-free mass in kg. If unknown, approximated from bodyweight for the RED-S floor check.
    public var fatFreeMassKg: Double?
    // Feature request — "add in a section asking them about their target weight and time period
    // as well. Use those to calculate their daily caloric intake." When both are set (cut/bulk
    // only — maintain/recomp don't have a literal weight target), these drive the calorie
    // deficit/surplus directly instead of Goal's fixed percentage; see
    // TDEECalculator.goalAdjustedTDEE. `weightKg` above is the anchor "starting point" for that
    // math — deliberately not re-derived from later weigh-ins, so the resulting daily calorie
    // figure stays fixed until the user explicitly changes goal/target/timeframe again.
    public var targetWeightKg: Double?
    public var targetWeeks: Int?

    public init(weightKg: Double, heightCm: Double, age: Int, sex: Sex, activityLevel: ActivityLevel, goal: Goal,
                fatFreeMassKg: Double? = nil, targetWeightKg: Double? = nil, targetWeeks: Int? = nil) {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.age = age
        self.sex = sex
        self.activityLevel = activityLevel
        self.goal = goal
        self.fatFreeMassKg = fatFreeMassKg
        self.targetWeightKg = targetWeightKg
        self.targetWeeks = targetWeeks
    }

    /// Falls back to 80% of bodyweight when body composition isn't known.
    var estimatedFatFreeMassKg: Double {
        fatFreeMassKg ?? weightKg * 0.8
    }
}
