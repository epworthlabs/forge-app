import SwiftUI
import ForgeCore

/// Feature request — "this figure should not change unless these settings are changed in the
/// app": the in-app place to actually change them, after onboarding. Mirrors onboarding's
/// GoalStep (same target-weight/timeframe-only-for-cut-bulk logic), routed through
/// `AppStore.updateGoalAndTarget` so it goes through the same persistence path as everything else.
struct GoalTargetEditSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    // Feature request — "users should be able to edit their current weight... in the goal &
    // target section as well. Make sure this is taken into account when determining target
    // calories." Distinct from `targetWeightLb` below (where you're trying to get to) — this is
    // where you are right now, which is what `TDEECalculator` actually uses for BMR/TDEE.
    @State private var currentWeightLb: Int = 150
    @State private var goal: Goal = .maintain
    @State private var targetWeightLb: Double = 150
    @State private var targetWeeks: Int = 12
    // Feature request — "protein intake seems a bit low, I want users to be able to adjust the
    // target macro splits manually if needed." Protein % and carb % are user-set; fat % is
    // derived as the remainder, so it's always exactly one free choice short of needing a
    // sum-to-100 validator.
    @State private var useCustomMacros = false
    @State private var proteinPercent = 30
    @State private var carbPercent = 40
    @State private var hasSeeded = false

    private var fatPercent: Int { max(0, 100 - proteinPercent - carbPercent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            Text("Goal & Target").font(ForgeType.title).foregroundStyle(ForgeColors.ink)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Current weight").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                        Spacer()
                        NumpadField(value: $currentWeightLb, maxDigits: 3, range: 50...600, suffix: "lb")
                    }
                    .padding(16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    ForEach([Goal.cut, .bulk, .recomp, .maintain], id: \.self) { g in
                        Button { goal = g } label: {
                            Text(g.displayLabel).font(ForgeType.body).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .foregroundStyle(goal == g ? Color.white : ForgeColors.ink)
                                .background { goal == g ? AnyView(ForgeColors.accent) : AnyView(Rectangle().fill(.ultraThinMaterial)) }
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if goal == .cut || goal == .bulk {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Target weight").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            Picker("Target weight (lb)", selection: Binding(
                                get: { Int(targetWeightLb.rounded()) },
                                set: { targetWeightLb = Double($0) }
                            )) {
                                ForEach(70...400, id: \.self) { lb in Text("\(lb) lb").tag(lb) }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 110)
                        }
                        .padding(16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Time period").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            Picker("Weeks", selection: $targetWeeks) {
                                ForEach(1...104, id: \.self) { w in Text("\(w) weeks").tag(w) }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 110)
                        }
                        .padding(16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Text("This sets your daily calorie target — it won't change again until you update your goal or target here.")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    }

                    Divider().overlay(ForgeColors.cardBorder).padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $useCustomMacros) {
                            Text("Custom macro split").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                        }
                        .tint(ForgeColors.accent)

                        if useCustomMacros {
                            Text("Percentages of your daily calories — this still moves with your Load Score day to day, only the split changes.")
                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)

                            macroPercentRow(label: "Protein", value: $proteinPercent, color: ForgeColors.accent)
                            macroPercentRow(label: "Carbs", value: $carbPercent, color: ForgeColors.accent2)
                            HStack {
                                Text("Fat").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                Spacer()
                                Text("\(fatPercent)%").font(ForgeType.body).foregroundStyle(ForgeColors.inkMuted)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }

            Button {
                store.updateCurrentWeight(Double(currentWeightLb))
                store.updateGoalAndTarget(goal: goal, targetWeightLb: targetWeightLb, targetWeeks: targetWeeks)
                if useCustomMacros {
                    store.updateMacroSplit(proteinPercent: Double(proteinPercent) / 100, carbPercent: Double(carbPercent) / 100, fatPercent: Double(fatPercent) / 100)
                } else {
                    store.updateMacroSplit(proteinPercent: nil, carbPercent: nil, fatPercent: nil)
                }
                dismiss()
            } label: {
                Text("Save").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .presentationDetents([.large])
        .onAppear {
            guard !hasSeeded else { return }
            hasSeeded = true
            currentWeightLb = WeightUnit.roundedLb(fromKg: store.profile.weightKg)
            goal = store.profile.goal
            targetWeightLb = (store.profile.targetWeightKg ?? store.profile.weightKg) / 0.45359237
            targetWeeks = store.profile.targetWeeks ?? 12
            if let p = store.profile.manualProteinPercent, let c = store.profile.manualCarbPercent, store.profile.manualFatPercent != nil {
                useCustomMacros = true
                proteinPercent = Int((p * 100).rounded())
                carbPercent = Int((c * 100).rounded())
            }
        }
    }

    private func macroPercentRow(label: String, value: Binding<Int>, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
            Spacer()
            IconButton(systemName: "minus", action: { value.wrappedValue = max(0, value.wrappedValue - 5) }, size: 36)
            NumpadField(value: value, maxDigits: 3, range: 0...100, suffix: "%")
            IconButton(systemName: "plus", action: { value.wrappedValue = min(100, value.wrappedValue + 5) }, size: 36)
        }
    }
}
