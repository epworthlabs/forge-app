import Foundation
import ForgeCore

struct ProgramTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let daysPerWeek: Int
    let weeks: Int
    var meta: String { "\(daysPerWeek) days/wk · \(weeks) weeks" }
}

extension ActivityLevel {
    var displayLabel: String {
        switch self {
        case .low: return "Low activity"
        case .moderate: return "Moderate activity"
        case .high: return "High activity"
        }
    }
}

extension Goal {
    var displayLabel: String {
        switch self {
        case .bulk: return "Build muscle"
        case .cut: return "Lose fat"
        case .recomp: return "Recomp"
        case .maintain: return "Maintain"
        }
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    static let templates: [ProgramTemplate] = [
        ProgramTemplate(id: "ppl", name: "Push/Pull/Legs — Strength", daysPerWeek: 6, weeks: 12),
        ProgramTemplate(id: "531", name: "5/3/1 for Beginners", daysPerWeek: 4, weeks: 16),
        ProgramTemplate(id: "ul", name: "Upper/Lower Hypertrophy", daysPerWeek: 4, weeks: 10),
    ]

    @Published var step: Int = 1
    @Published var weightLb: Double = 178
    @Published var activityLevel: ActivityLevel?
    @Published var goal: Goal?
    @Published var trainingDaysPerWeek: Int?
    @Published var selectedProgram: ProgramTemplate?

    var canContinueFromGoal: Bool { goal != nil }
    var canEnterApp: Bool { selectedProgram != nil }

    func adjustWeight(by delta: Double) {
        weightLb = max(90, weightLb + delta)
    }

    /// Onboarding's whole reason for being one flow, not two — this seeds both the program
    /// selection and, via ForgeCore, the baseline nutrition target in a single pass.
    func buildProfile(heightCm: Double, age: Int, sex: Sex) -> UserProfile? {
        guard let goal, let activityLevel else { return nil }
        let weightKg = weightLb * 0.45359237
        return UserProfile(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex,
                            activityLevel: activityLevel, goal: goal)
    }
}
