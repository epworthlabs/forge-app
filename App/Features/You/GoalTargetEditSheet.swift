import SwiftUI
import ForgeCore

/// Feature request — "this figure should not change unless these settings are changed in the
/// app": the in-app place to actually change them, after onboarding. Mirrors onboarding's
/// GoalStep (same target-weight/timeframe-only-for-cut-bulk logic), routed through
/// `AppStore.updateGoalAndTarget` so it goes through the same persistence path as everything else.
struct GoalTargetEditSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var goal: Goal = .maintain
    @State private var targetWeightLb: Double = 150
    @State private var targetWeeks: Int = 12
    @State private var hasSeeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            Text("Goal & Target").font(ForgeType.title).foregroundStyle(ForgeColors.ink)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach([Goal.cut, .bulk, .recomp, .maintain], id: \.self) { g in
                        Button { goal = g } label: {
                            Text(g.displayLabel).font(ForgeType.body).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
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
                }
            }

            Button {
                store.updateGoalAndTarget(goal: goal, targetWeightLb: targetWeightLb, targetWeeks: targetWeeks)
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
            goal = store.profile.goal
            targetWeightLb = (store.profile.targetWeightKg ?? store.profile.weightKg) / 0.45359237
            targetWeeks = store.profile.targetWeeks ?? 12
        }
    }
}
