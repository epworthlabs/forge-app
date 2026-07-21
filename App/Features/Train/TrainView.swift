import SwiftUI
import ForgeCore

struct TrainView: View {
    @EnvironmentObject var store: AppStore
    @State private var addingExercise = false
    @State private var editingProgram = false

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(store.program.name) · \(store.currentProgramDayName)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            Text("Log Workout").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                        }
                        Spacer()
                        // Feature request — "editable timeframe... customize or copy over to
                        // future weeks." Durable program edits, distinct from swap/add/remove in
                        // ExerciseCard below, which only affect today's session.
                        Button { editingProgram = true } label: {
                            Text("Edit Program").font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }

                    // FRG-206 — a scheduled deload week, not a missed one; surfaced so a lighter
                    // Load Score today reads as intentional rather than a tracking gap.
                    if store.isDeloadWeek {
                        HStack(spacing: 8) {
                            Image(systemName: "leaf.fill").foregroundStyle(ForgeColors.accent).font(.caption)
                            Text("Deload week — planned lighter load").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }
                    }

                    // FRG-111 — ticks every second off the current clock rather than a decremented
                    // stored counter, so the label is always correct even after backgrounding for
                    // a while mid-rest (a stored countdown would just freeze while backgrounded).
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("REST").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                    Text(restLabel).font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
                                }
                                Spacer()
                                Button("Reset") { store.restEndDate = Date().addingTimeInterval(105) }
                                    .font(ForgeType.body).foregroundStyle(ForgeColors.accent)
                            }
                        }
                    }

                    ForEach(store.todaysExercises) { slot in
                        ExerciseCard(slot: slot)
                    }

                    // Feature request — session-only: adds to today's workout, doesn't touch the
                    // program definition (see AppStore.addExercise doc comment).
                    Button { addingExercise = true } label: {
                        Text("+ Add Exercise").font(ForgeType.body).frame(maxWidth: .infinity)
                            .padding(14).foregroundStyle(ForgeColors.inkMuted)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(dash: [5, 4])))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.finishWorkout()
                    } label: {
                        Text("Finish Workout").font(ForgeType.title).frame(maxWidth: .infinity)
                            .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.todaysExercises.contains { $0.sets.contains(where: \.done) })
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $addingExercise) {
            ExercisePickerSheet { exercise in
                store.addExercise(exercise)
            }
        }
        .sheet(isPresented: $editingProgram) {
            ProgramEditorView(existingProgram: store.program) { updatedProgram in
                store.updateProgram(updatedProgram)
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
    @State private var suggestionDismissed = false
    @State private var editingSets = false
    @State private var swappingExercise = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.exercise.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                        Text("\(slot.targetSets)×\(slot.targetReps) @ \(Int(slot.targetWeightKg)) kg")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    }
                    Spacer()
                    Menu {
                        Button("Swap Exercise") { swappingExercise = true }
                        Button(editingSets ? "Done Editing" : "Edit Sets") { editingSets.toggle() }
                        Button("Remove Exercise", role: .destructive) { store.removeExercise(exerciseID: slot.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(ForgeColors.inkMuted).font(.body)
                    }
                }

                // FRG-112 — reference from training history; nil until this exercise has been
                // logged at least once before.
                if let lastPerformance = slot.lastPerformance {
                    Text("Last time: \(lastPerformance)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }

                // FRG-113 — editable suggestion, never auto-applied. Hidden once dismissed or once
                // every set is already done (nothing left to apply it to).
                if !suggestionDismissed, let suggestion = store.suggestion(for: slot), slot.sets.contains(where: { !$0.done }) {
                    SuggestionCard(suggestion: suggestion) {
                        store.applySuggestion(suggestion, exerciseID: slot.id)
                        suggestionDismissed = true
                    } onDismiss: {
                        suggestionDismissed = true
                    }
                }

                ForEach(slot.sets) { set in
                    if editingSets {
                        EditableSetRow(exerciseID: slot.id, set: set, canRemove: slot.sets.count > 1)
                    } else {
                        SetRow(exerciseID: slot.id, set: set)
                    }
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
        .sheet(isPresented: $swappingExercise) {
            ExercisePickerSheet { exercise in
                store.swapExercise(exerciseID: slot.id, with: exercise)
            }
        }
    }
}

private struct SuggestionCard: View {
    let suggestion: ProgressiveOverloadEngine.Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUGGESTED NEXT SET").font(ForgeType.label).foregroundStyle(ForgeColors.accent)
            Text("\(Int(suggestion.weightKg)) kg × \(suggestion.reps)").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
            HStack(spacing: 8) {
                Button("Accept", action: onAccept)
                    .font(ForgeType.caption).foregroundStyle(Color.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(ForgeColors.accent).clipShape(Capsule())
                Button("Dismiss", action: onDismiss)
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(ForgeColors.cardBorder))
            }
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ForgeColors.accent.opacity(0.4)))
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

/// Feature request — swaps the normal tap-to-complete row for direct weight/reps editing plus a
/// remove button, while "Edit Sets" is toggled on for this exercise.
private struct EditableSetRow: View {
    @EnvironmentObject var store: AppStore
    let exerciseID: ExerciseSlot.ID
    let set: LoggedSet
    let canRemove: Bool

    var body: some View {
        HStack(spacing: 10) {
            Stepper(value: Binding(
                get: { set.weightKg },
                set: { store.updateSet(exerciseID: exerciseID, setID: set.id, weightKg: $0, reps: set.reps) }
            ), in: 0...500, step: 2.5) {
                Text("\(Int(set.weightKg)) kg").font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
            }
            Stepper(value: Binding(
                get: { set.reps },
                set: { store.updateSet(exerciseID: exerciseID, setID: set.id, weightKg: set.weightKg, reps: $0) }
            ), in: 1...50) {
                Text("\(set.reps) reps").font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
            }
            if canRemove {
                Button { store.removeSet(exerciseID: exerciseID, setID: set.id) } label: {
                    Image(systemName: "trash").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
