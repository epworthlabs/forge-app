import SwiftUI
import ForgeCore

struct TargetExplanationSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let target = store.nutritionTarget
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            Text("Why did my target change?").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
                .padding(.bottom, 6)

            ExplanationRow(label: "Baseline (maintenance)", value: "\(Int(target.baselineMaintenanceCalories)) kcal")
            ExplanationRow(label: "Today's Load Score", value: String(format: "%.1f× %@", target.loadScore, loadDescriptor(target.loadScore)), accent: true)
            ExplanationRow(label: "Adjustment", value: adjustmentText(target))
            ExplanationRow(label: "Protein (unchanged)", value: "\(Int(target.proteinG))g anchor", muted: true)

            if target.redSFloorApplied {
                Text("Your target was held at a safety floor today rather than reduced further, regardless of Load Score.")
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted).padding(.top, 8)
            }
        }
        .padding(22)
        .presentationDetents([.medium])
    }

    private func loadDescriptor(_ score: Double) -> String {
        switch score {
        case ..<0.7: return "(light)"
        case 0.7..<1.3: return "(typical)"
        default: return "(heavy)"
        }
    }

    private func adjustmentText(_ target: NutritionTarget) -> String {
        let sign = target.calorieAdjustment >= 0 ? "+" : ""
        return "\(sign)\(Int(target.calorieAdjustment)) kcal"
    }
}

private struct ExplanationRow: View {
    let label: String
    let value: String
    var accent: Bool = false
    var muted: Bool = false
    var body: some View {
        HStack {
            Text(label).font(ForgeType.body).foregroundStyle(muted ? ForgeColors.inkMuted : ForgeColors.ink)
            Spacer()
            Text(value).font(ForgeType.body).foregroundStyle(accent ? ForgeColors.accent : (muted ? ForgeColors.inkMuted : ForgeColors.ink))
        }
        .padding(.vertical, 9)
        .overlay(Rectangle().fill(ForgeColors.cardBorder).frame(height: 1), alignment: .bottom)
    }
}
