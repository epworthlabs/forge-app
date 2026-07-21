import SwiftUI
import UIKit
import ForgeCore

/// Feature request — "[program selection] should be the screen that initiates and funnels down
/// to the other screens." Train's root: ProgramSelectionView -> DaySelectionView -> TrainSessionView,
/// with WorkoutCompleteView as a full-screen cover after Finish Workout that hands back to
/// DaySelectionView (item 3: review the just-finished session, or pick a different day).
struct TrainView: View {
    @EnvironmentObject var store: AppStore
    @State private var path: [TrainRoute] = []
    @State private var showingCompleteScreen = false

    var body: some View {
        NavigationStack(path: $path) {
            ProgramSelectionView {
                path.append(.daySelection)
            }
            .navigationDestination(for: TrainRoute.self) { route in
                switch route {
                case .daySelection:
                    DaySelectionView(
                        onSelectDay: { index in
                            store.selectDay(index)
                            path.append(.session)
                        },
                        onReview: { path.append(.review) }
                    )
                case .session:
                    TrainSessionView {
                        showingCompleteScreen = true
                    }
                case .review:
                    SessionReviewView()
                }
            }
        }
        .fullScreenCover(isPresented: $showingCompleteScreen) {
            WorkoutCompleteView {
                showingCompleteScreen = false
                // Item 3 — back to day selection so they can review what they just did or pick
                // something else, rather than dumping them back into an empty logging screen.
                path = [.daySelection]
            }
        }
    }
}

private enum TrainRoute: Hashable {
    case daySelection
    case session
    case review
}

/// The actual per-day logging screen — exercise cards, rest timer, Finish Workout. Reached via
/// DaySelectionView, never directly from the tab bar anymore.
struct TrainSessionView: View {
    @EnvironmentObject var store: AppStore
    var onFinished: () -> Void

    @State private var addingExercise = false
    @State private var editingProgram = false
    @State private var editingRestDuration = false
    @State private var showFutureWeeksPromptForAdd = false

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

                    RestTimerCard(editingRestDuration: $editingRestDuration)

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
                        onFinished()
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
        .navigationTitle(store.currentProgramDayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingExercise) {
            ExercisePickerSheet { exercise in
                store.addExercise(exercise)
                showFutureWeeksPromptForAdd = true
            }
        }
        .sheet(isPresented: $editingProgram) {
            ProgramEditorView(existingProgram: store.program) { updatedProgram in
                store.updateProgram(updatedProgram)
            }
        }
        .sheet(isPresented: $editingRestDuration) {
            RestDurationSheet(seconds: store.restDurationSeconds) { newSeconds in
                store.restDurationSeconds = newSeconds
            }
        }
        .futureWeeksPrompt(isPresented: $showFutureWeeksPromptForAdd, store: store)
    }
}

/// Feature request — "allow users to edit rest timer" + "when rest ends, provide a vibrate and go
/// into negative timing." `TimelineView` re-evaluates every second, which is what both the
/// countdown display and the one-shot haptic (`.task(id:)`, fires once per distinct value) depend
/// on — a plain `@State` timer would freeze while the app is backgrounded.
private struct RestTimerCard: View {
    @EnvironmentObject var store: AppStore
    @Binding var editingRestDuration: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = store.restSecondsRemaining
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REST").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                        Text(label(for: remaining)).font(ForgeType.displayMedium)
                            .foregroundStyle(remaining < 0 ? Color.red : ForgeColors.ink)
                    }
                    Spacer()
                    Button { editingRestDuration = true } label: {
                        Image(systemName: "pencil").font(.caption).foregroundStyle(ForgeColors.inkMuted)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    Button("Reset") { store.restEndDate = Date().addingTimeInterval(TimeInterval(store.restDurationSeconds)) }
                        .font(ForgeType.body).foregroundStyle(ForgeColors.accent)
                }
            }
            .task(id: remaining) {
                if remaining == 0 { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            }
        }
    }

    private func label(for remaining: Int) -> String {
        let overtime = remaining < 0
        let displaySeconds = abs(remaining)
        let m = displaySeconds / 60, s = displaySeconds % 60
        return (overtime ? "+" : "") + String(format: "%d:%02d", m, s)
    }
}

private struct RestDurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let seconds: Int
    var onSave: (Int) -> Void
    @State private var selected: Int

    init(seconds: Int, onSave: @escaping (Int) -> Void) {
        self.seconds = seconds
        self.onSave = onSave
        _selected = State(initialValue: seconds)
    }

    private let options = Array(stride(from: 0, through: 600, by: 15))

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            Text("Rest duration").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
            // Scrollable wheel, not a stepper — every value directly reachable.
            Picker("Rest duration", selection: $selected) {
                ForEach(options, id: \.self) { s in
                    Text(String(format: "%d:%02d", s / 60, s % 60)).tag(s)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 140)
            Button {
                onSave(selected)
                dismiss()
            } label: {
                Text("Save").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .presentationDetents([.height(320)])
    }
}

/// Feature request — "allow them to change it for future weeks if needed." Session-only edits
/// (swap/add/remove exercise, or finishing a sets/reps/weight edit) default to today only, same
/// as before; this is the opt-in prompt to also promote the change into the program itself.
private extension View {
    func futureWeeksPrompt(isPresented: Binding<Bool>, store: AppStore) -> some View {
        confirmationDialog(
            "Also update your program for this week and beyond?",
            isPresented: isPresented, titleVisibility: .visible
        ) {
            Button("This week & beyond") { store.applyTodaysChangesToFutureWeeks() }
            Button("Just this session", role: .cancel) {}
        }
    }
}

private struct ExerciseCard: View {
    @EnvironmentObject var store: AppStore
    let slot: ExerciseSlot
    @State private var suggestionDismissed = false
    @State private var editingSets = false
    @State private var swappingExercise = false
    @State private var showFutureWeeksPrompt = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.exercise.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                        Text("\(slot.targetSets)×\(slot.targetReps) @ \(WeightUnit.roundedLb(fromKg: slot.targetWeightKg)) lb")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    }
                    Spacer()
                    Menu {
                        Button("Swap Exercise") { swappingExercise = true }
                        if !editingSets {
                            Button("Edit Sets") { editingSets = true }
                        }
                        Button("Remove Exercise", role: .destructive) {
                            store.removeExercise(exerciseID: slot.id)
                            showFutureWeeksPrompt = true
                        }
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

                if editingSets {
                    // Feature request — a dedicated, visible confirm action rather than only the
                    // toggle buried in the ⋯ menu; also the point at which we ask whether these
                    // set/rep/weight edits should carry forward into the program itself.
                    Button {
                        editingSets = false
                        showFutureWeeksPrompt = true
                    } label: {
                        Text("Done Editing").font(ForgeType.body).frame(maxWidth: .infinity)
                            .padding(12).foregroundStyle(Color.white).background(ForgeColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
                showFutureWeeksPrompt = true
            }
        }
        .futureWeeksPrompt(isPresented: $showFutureWeeksPrompt, store: store)
    }
}

private struct SuggestionCard: View {
    let suggestion: ProgressiveOverloadEngine.Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUGGESTED NEXT SET").font(ForgeType.label).foregroundStyle(ForgeColors.accent)
            Text("\(WeightUnit.roundedLb(fromKg: suggestion.weightKg)) lb × \(suggestion.reps)").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
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
                    Text("\(WeightUnit.roundedLb(fromKg: set.weightKg)) lb × \(set.reps)")
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
                get: { WeightUnit.lb(fromKg: set.weightKg) },
                set: { store.updateSet(exerciseID: exerciseID, setID: set.id, weightKg: WeightUnit.kg(fromLb: $0), reps: set.reps) }
            ), in: 0...1100, step: 5) {
                Text("\(WeightUnit.roundedLb(fromKg: set.weightKg)) lb").font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
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
