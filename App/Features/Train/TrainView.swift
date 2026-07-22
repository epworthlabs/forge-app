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
                        onSelectDay: { index, week in
                            store.selectDay(index, week: week)
                            path.append(.session)
                        },
                        onReview: { path.append(.review) }
                    )
                case .session:
                    TrainSessionView {
                        showingCompleteScreen = true
                    }
                case .review:
                    if let session = store.lastCompletedSession {
                        SessionReviewView(session: session)
                    }
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
    // Bug fix — this used to live on each ExerciseCard, which broke the prompt entirely: removing
    // or swapping an exercise mutates `todaysExercises`, which tears down (remove) or recreates
    // (swap — see AppStore.swapExercise's id-preservation fix) that specific card's view instance
    // before its own confirmationDialog/alert ever got a chance to render. Living here instead,
    // on the parent that's never destroyed by that mutation, is what actually makes it show up.
    @State private var showFutureWeeksPrompt = false

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
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
                            Text("Edit Program").font(ForgeType.body).foregroundStyle(ForgeColors.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
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
                        ExerciseCard(slot: slot, onLineupChanged: { showFutureWeeksPrompt = true })
                    }

                    // Feature request — session-only: adds to today's workout, doesn't touch the
                    // program definition (see AppStore.addExercise doc comment).
                    DashedActionButton(title: "+ Add Exercise") { addingExercise = true }

                    Button {
                        store.finishWorkout()
                        onFinished()
                    } label: {
                        Text("Finish Workout").font(ForgeType.title).frame(maxWidth: .infinity)
                            .padding(18).foregroundStyle(Color.white).background(ForgeColors.accent)
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
                showFutureWeeksPrompt = true
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
        .futureWeeksAlert(isPresented: $showFutureWeeksPrompt, store: store)
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
                    IconButton(systemName: "pencil", action: { editingRestDuration = true }, size: 40)
                    Button("Reset") { store.restEndDate = Date().addingTimeInterval(TimeInterval(store.restDurationSeconds)) }
                        .font(ForgeType.body).foregroundStyle(ForgeColors.accent)
                        .padding(.horizontal, 6)
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

/// Feature request — "allow them to change it for future weeks if needed" + "change the prompt...
/// to an actual window" (an `.alert`, not the bottom-sheet-style `.confirmationDialog` it was).
private extension View {
    func futureWeeksAlert(isPresented: Binding<Bool>, store: AppStore) -> some View {
        alert("Update Your Program?", isPresented: isPresented) {
            Button("This Week & Beyond") { store.applyTodaysChangesToFutureWeeks() }
            Button("Just This Session", role: .cancel) {}
        } message: {
            Text("Apply this change to your program for this week and beyond, or keep it to just today's session?")
        }
    }
}

private struct ExerciseCard: View {
    @EnvironmentObject var store: AppStore
    let slot: ExerciseSlot
    var onLineupChanged: () -> Void
    @State private var suggestionDismissed = false
    @State private var swappingExercise = false

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
                        Button("Remove Exercise", role: .destructive) {
                            store.removeExercise(exerciseID: slot.id)
                            onLineupChanged()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(ForgeColors.inkMuted).font(.system(size: 20))
                            .frame(width: 44, height: 44)
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

                // Feature request — "the reps and weights in the training tracker needs to be
                // adjustable without adding an edit flow." Previously required toggling "Edit
                // Sets" (a separate mode swapping in a different row type) before weight/reps
                // could be touched at all — every row is now always directly adjustable, no mode
                // switch. This also merges the old "Edit Sets"-only remove-set capability in.
                ForEach(slot.sets) { set in
                    SetRow(exerciseID: slot.id, set: set, canRemove: slot.sets.count > 1)
                }

                DashedActionButton(title: "+ Add Set") { store.addSet(exerciseID: slot.id) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $swappingExercise) {
            ExercisePickerSheet { exercise in
                store.swapExercise(exerciseID: slot.id, with: exercise)
                onLineupChanged()
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
            Text("\(WeightUnit.roundedLb(fromKg: suggestion.weightKg)) lb × \(suggestion.reps)").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
            HStack(spacing: 10) {
                Button("Accept", action: onAccept)
                    .font(ForgeType.body).foregroundStyle(Color.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(ForgeColors.accent).clipShape(Capsule())
                Button("Dismiss", action: onDismiss)
                    .font(ForgeType.body).foregroundStyle(ForgeColors.inkMuted)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .overlay(Capsule().strokeBorder(ForgeColors.cardBorder))
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ForgeColors.accent.opacity(0.4)))
    }
}

/// Feature request — "the reps and weights in the training tracker needs to be adjustable
/// without adding an edit flow." Merges the old tap-to-complete row and the separate
/// "Edit Sets"-only row into one: weight/reps are always directly adjustable, no mode toggle.
/// RPE is also "made optional... hide it somewhere" — collapsed by default behind a small
/// "+ RPE" link once a set is marked done, instead of auto-expanding a 1-10 picker on everyone.
private struct SetRow: View {
    @EnvironmentObject var store: AppStore
    let exerciseID: ExerciseSlot.ID
    let set: LoggedSet
    let canRemove: Bool
    @State private var rpeExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    store.toggleSet(exerciseID: exerciseID, setID: set.id)
                } label: {
                    Circle()
                        .strokeBorder(set.done ? ForgeColors.accent : ForgeColors.inkMuted, lineWidth: 2)
                        .background(Circle().fill(set.done ? ForgeColors.accent : Color.clear))
                        .frame(width: 24, height: 24)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -6)

                WeightNumberField(weightLb: Binding(
                    get: { WeightUnit.lb(fromKg: set.weightKg) },
                    set: { store.updateSet(exerciseID: exerciseID, setID: set.id, weightKg: WeightUnit.kg(fromLb: $0), reps: set.reps) }
                ))
                RepsNumberField(reps: Binding(
                    get: { set.reps },
                    set: { store.updateSet(exerciseID: exerciseID, setID: set.id, weightKg: set.weightKg, reps: $0) }
                ))

                if canRemove {
                    Button { store.removeSet(exerciseID: exerciseID, setID: set.id) } label: {
                        Image(systemName: "trash").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(9)
            .background(set.done ? ForgeColors.tileBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // RPE — "make the RPE optional as well, can we hide it somewhere" — collapsed behind
            // a small link rather than auto-expanding a 1-10 picker the moment a set is done.
            if set.done {
                Button {
                    rpeExpanded.toggle()
                } label: {
                    Text(set.rpe.map { "RPE \(String(format: "%.0f", $0))" } ?? "+ RPE")
                        .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }
                .buttonStyle(.plain)
                .padding(.leading, 26)

                if rpeExpanded {
                    RPEPicker(value: set.rpe ?? 8) { newValue in
                        store.updateRPE(exerciseID: exerciseID, setID: set.id, rpe: newValue)
                    }
                    .padding(.leading, 26)
                }
            }
        }
    }
}

/// Feature request — "a numpad to come up when inputting weights, keep the +/- of 5lb increments
/// as well." A digit-filtered numeric-keypad TextField for typing an exact number directly,
/// flanked by the existing quick-adjust buttons for small corrections mid-set. Clears on focus —
/// "I don't want to have to select the number when editing the field, just want the numpad to
/// pull up and the field to edit when I start entering numbers" — so the first digit typed
/// replaces the old value instead of appending to it.
private struct WeightNumberField: View {
    @Binding var weightLb: Double
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Button { weightLb = max(0, weightLb - 5) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(ForgeColors.ink)
                    .frame(width: 24, height: 24).background(ForgeColors.cardBackground).clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
                    .frame(width: 34)
                    .focused($isFocused)
                    .numpadDoneButton(isFocused: $isFocused)
                    .onAppear { text = String(Int(weightLb.rounded())) }
                    .onChange(of: weightLb) { newValue in
                        if !isFocused { text = String(Int(newValue.rounded())) }
                    }
                    .onChange(of: isFocused) { focused in
                        if focused {
                            text = ""
                        } else if text.isEmpty {
                            text = String(Int(weightLb.rounded()))
                        }
                    }
                    .onChange(of: text) { newText in
                        let digits = newText.filter(\.isNumber)
                        if digits != newText { text = digits }
                        guard let parsed = Double(digits) else { return }
                        weightLb = min(1100, max(0, parsed))
                    }
                Text("lb").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }

            Button { weightLb = min(1100, weightLb + 5) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(ForgeColors.ink)
                    .frame(width: 24, height: 24).background(ForgeColors.cardBackground).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Same clear-on-focus typed-entry pattern as `WeightNumberField`, for reps — "make the numpad
/// entering more intuitive when editing weights and reps," matching formatting/sizing exactly so
/// the row reads as one consistent control, not two different styles.
private struct RepsNumberField: View {
    @Binding var reps: Int
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Button { reps = max(1, reps - 1) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(ForgeColors.ink)
                    .frame(width: 24, height: 24).background(ForgeColors.cardBackground).clipShape(Circle())
            }
            .buttonStyle(.plain)

            // No "reps" suffix here (unlike weight's "lb") — space is tight once this sits in the
            // same row as the done-circle, weight, and trash; a bare count reads fine positioned
            // right after weight with its own matching ± pair.
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
                .frame(width: 20)
                .focused($isFocused)
                .numpadDoneButton(isFocused: $isFocused)
                .onAppear { text = String(reps) }
                .onChange(of: reps) { newValue in
                    if !isFocused { text = String(newValue) }
                }
                .onChange(of: isFocused) { focused in
                    if focused {
                        text = ""
                    } else if text.isEmpty {
                        text = String(reps)
                    }
                }
                .onChange(of: text) { newText in
                    let digits = newText.filter(\.isNumber)
                    if digits != newText { text = digits }
                    guard let parsed = Int(digits) else { return }
                    reps = min(50, max(1, parsed))
                }

            Button { reps = min(50, reps + 1) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(ForgeColors.ink)
                    .frame(width: 24, height: 24).background(ForgeColors.cardBackground).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RPEPicker: View {
    let value: Double
    let onChange: (Double) -> Void
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { n in
                Button {
                    onChange(Double(n))
                } label: {
                    Text("\(n)")
                        .font(ForgeType.caption)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Int(value) == n ? Color.white : ForgeColors.inkMuted)
                        .background(Int(value) == n ? ForgeColors.accent : ForgeColors.tileBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
