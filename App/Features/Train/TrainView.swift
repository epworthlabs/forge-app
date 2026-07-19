import SwiftUI
import ForgeCore

struct TrainView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.program.name).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        Text("Log Workout").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                    }

                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("REST").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                Text(restLabel).font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
                            }
                            Spacer()
                            Button("Reset") { store.restSecondsRemaining = 105 }
                                .font(ForgeType.body).foregroundStyle(ForgeColors.accent)
                        }
                    }

                    ForEach(store.todaysExercises) { slot in
                        ExerciseCard(slot: slot)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
    }

    private var restLabel: String {
        let m = store.restSecondsRemaining / 60, s = store.restSecondsRemaining % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct ExerciseCard: View {
    @EnvironmentObject var store: AppStore
    let slot: ExerciseSlot

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(slot.exercise.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Text("\(slot.targetSets)×\(slot.targetReps) @ \(Int(slot.targetWeightKg)) kg")
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)

                ForEach(slot.sets) { set in
                    SetRow(exerciseID: slot.id, set: set)
                }

                Button {
                    store.addSet(exerciseID: slot.id)
                } label: {
                    Text("+ Add Set").font(ForgeType.caption).frame(maxWidth: .infinity)
                        .padding(10).foregroundStyle(ForgeColors.inkMuted)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(dash: [4, 4])))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SetRow: View {
    @EnvironmentObject var store: AppStore
    let exerciseID: ExerciseSlot.ID
    let set: LoggedSet

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                store.toggleSet(exerciseID: exerciseID, setID: set.id)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(set.done ? ForgeColors.accent : ForgeColors.inkMuted, lineWidth: 1.5)
                        .background(Circle().fill(set.done ? ForgeColors.accent : Color.clear))
                        .frame(width: 16, height: 16)
                    Text("\(Int(set.weightKg)) kg × \(set.reps)")
                        .font(ForgeType.body)
                        .foregroundStyle(set.done ? ForgeColors.ink : ForgeColors.inkMuted)
                    Spacer()
                    if let rpe = set.rpe {
                        Text("RPE \(String(format: "%.0f", rpe))").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    }
                }
                .padding(9)
                .background(set.done ? ForgeColors.tileBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            // RPE input surfaces once a set is marked done — logged as effort, not a required
            // pre-condition, so a quick tap-to-complete flow stays fast between sets.
            if set.done {
                RPEPicker(value: set.rpe ?? 8) { newValue in
                    store.updateRPE(exerciseID: exerciseID, setID: set.id, rpe: newValue)
                }
                .padding(.leading, 26)
            }
        }
    }
}

private struct RPEPicker: View {
    let value: Double
    let onChange: (Double) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...10, id: \.self) { n in
                Button {
                    onChange(Double(n))
                } label: {
                    Text("\(n)")
                        .font(ForgeType.caption)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Int(value) == n ? Color.white : ForgeColors.inkMuted)
                        .background(Int(value) == n ? ForgeColors.accent : ForgeColors.tileBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
