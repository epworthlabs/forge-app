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
            // Feature request — "get rid of adjustments that happen to calorie amounts after
            // training... the calorie amounts were not supposed to change." This sheet used to
            // explain a same-day Load Score swing; the target is now fixed by activity level +
            // goal + weekly recalibration, so it's a plain breakdown, not a "why did this change"
            // explanation — renamed and dropped the Load Score/Adjustment rows and the
            // sleep-recovery note, all of which only ever described that swing.
            Text("Your Nutrition Target").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
                .padding(.bottom, 6)

            ExplanationRow(label: "Baseline (maintenance)", value: "\(Int(target.baselineMaintenanceCalories)) kcal")
            if target.weeklyRecalibrationKcal != 0 {
                ExplanationRow(label: "Weekly trend recalibration", value: signedKcal(target.weeklyRecalibrationKcal))
            }
            ExplanationRow(label: "Protein (unchanged)", value: "\(Int(target.proteinG))g anchor", muted: true)

            if target.redSFloorApplied {
                Text("Your target was held at a safety floor rather than reduced further.")
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted).padding(.top, 8)
            }

            Text("Trakt's targets are estimates based on general formulas, not medical advice. Talk to a doctor or registered dietitian before making significant changes to your diet.")
                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted).padding(.top, 12)
        }
        .padding(22)
        .presentationDetents([.medium])
    }

    private func signedKcal(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value)) kcal"
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
