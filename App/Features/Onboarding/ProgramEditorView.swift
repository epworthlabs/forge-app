import SwiftUI
import UIKit
import ForgeCore

/// FRG-104 (create) / Feature request (edit) — one editor for both: building a brand-new custom
/// program at onboarding, and editing an existing program's timeframe/weeks from Train. Working
/// state materializes every week 1...weekCount into `weeks` (seeding an unset week from whatever
/// it currently resolves to) so editing and "copy to future weeks" can work uniformly; on save,
/// week 1 becomes `defaultDays` and any other week identical to it is dropped rather than stored
/// as a redundant override, keeping `ProgramTemplate.weekOverrides` sparse.
struct ProgramEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var existingProgram: ProgramTemplate?
    var onSave: (ProgramTemplate) -> Void

    @State private var programName: String
    @State private var weekCount: Int
    @State private var weeks: [Int: [ProgramDay]]
    @State private var selectedWeek: Int = 1
    @State private var pickingExerciseForDayID: String?
    @State private var copyConfirmationShown = false
    // FRG-206 — previously only settable via direct construction (the curated 5/3/1 template);
    // exposed here so a custom program can schedule deloads too.
    @State private var deloadEnabled: Bool
    @State private var deloadEveryNWeeks: Int

    init(existingProgram: ProgramTemplate? = nil, onSave: @escaping (ProgramTemplate) -> Void) {
        self.existingProgram = existingProgram
        self.onSave = onSave
        _programName = State(initialValue: existingProgram?.name ?? "My Program")
        _weekCount = State(initialValue: existingProgram?.weekCount ?? 8)
        _deloadEnabled = State(initialValue: existingProgram?.deloadEveryNWeeks != nil)
        _deloadEveryNWeeks = State(initialValue: existingProgram?.deloadEveryNWeeks ?? 4)
        if let existingProgram {
            var seeded: [Int: [ProgramDay]] = [:]
            for week in 1...max(1, existingProgram.weekCount) {
                seeded[week] = existingProgram.days(forWeek: week)
            }
            _weeks = State(initialValue: seeded)
        } else {
            _weeks = State(initialValue: [1: [ProgramDay(name: "Day 1", exercises: [])]])
        }
    }

    private var currentDaysBinding: Binding<[ProgramDay]> {
        Binding(
            get: { weeks[selectedWeek] ?? weeks[1] ?? [] },
            set: { weeks[selectedWeek] = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundWash
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SelectAllTextField(text: $programName, placeholder: "Program name", font: ForgeType.titleUIFont)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Feature request — "editable timeframe" + numpad entry, not a Stepper —
                        // ranging up to 52 one tap at a time is tedious.
                        HStack {
                            Text("Timeframe").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            Spacer()
                            NumberField(value: Binding(
                                get: { weekCount },
                                set: { newCount in
                                    let clamped = max(1, newCount)
                                    if clamped > weekCount {
                                        for week in (weekCount + 1)...clamped { weeks[week] = weeks[1] ?? [] }
                                    } else if clamped < weekCount {
                                        for week in (clamped + 1)...weekCount { weeks[week] = nil }
                                    }
                                    weekCount = clamped
                                    if selectedWeek > clamped { selectedWeek = clamped }
                                }
                            ), range: 1...52, suffix: "wk")
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // FRG-206 — scheduled deloads, previously only settable on the curated
                        // 5/3/1 template via direct construction, not from the editor.
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $deloadEnabled) {
                                Text("Scheduled deloads").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            }
                            .tint(ForgeColors.accent)
                            if deloadEnabled {
                                HStack {
                                    Text("Every").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    Spacer()
                                    NumberField(value: $deloadEveryNWeeks, range: 2...12, suffix: "wk")
                                }
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Week picker.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(1...weekCount, id: \.self) { week in
                                    Button { selectedWeek = week } label: {
                                        Text("Week \(week)")
                                            .font(ForgeType.caption).fontWeight(week == selectedWeek ? .bold : .regular)
                                            .foregroundStyle(week == selectedWeek ? Color.white : ForgeColors.ink)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(week == selectedWeek ? ForgeColors.accent : ForgeColors.tileBackground)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if weekCount > selectedWeek {
                            Button {
                                copyConfirmationShown = true
                            } label: {
                                Text("Copy Week \(selectedWeek) to all future weeks").font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog(
                                "Copy Week \(selectedWeek)'s exercises to weeks \(selectedWeek + 1)–\(weekCount)? This replaces their current content.",
                                isPresented: $copyConfirmationShown, titleVisibility: .visible
                            ) {
                                Button("Copy") {
                                    let source = currentDaysBinding.wrappedValue
                                    for week in (selectedWeek + 1)...weekCount { weeks[week] = source }
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                        }

                        ForEach(currentDaysBinding) { $day in
                            DayEditor(
                                day: $day,
                                onAddExercise: { pickingExerciseForDayID = day.id },
                                onDeleteDay: currentDaysBinding.wrappedValue.count > 1 ? { currentDaysBinding.wrappedValue.removeAll { $0.id == day.id } } : nil
                            )
                        }

                        Button {
                            currentDaysBinding.wrappedValue.append(ProgramDay(name: "Day \(currentDaysBinding.wrappedValue.count + 1)", exercises: []))
                        } label: {
                            Text("+ Add Day").font(ForgeType.body).frame(maxWidth: .infinity)
                                .padding(12).foregroundStyle(ForgeColors.inkMuted)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(dash: [5, 4])))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onSave(collapsedProgram())
                            dismiss()
                        } label: {
                            Text("Save Program").font(ForgeType.title).frame(maxWidth: .infinity)
                                .padding(16).foregroundStyle(Color.white)
                        }
                        .buttonStyle(LiquidPrimaryButtonStyle())
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                    }
                    .padding(20)
                }
                .dismissKeyboardOnTap()
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle(existingProgram == nil ? "Build Program" : "Edit Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: Binding(get: { pickingExerciseForDayID != nil }, set: { if !$0 { pickingExerciseForDayID = nil } })) {
                ExercisePickerSheet { exercise in
                    guard let dayID = pickingExerciseForDayID,
                          let idx = currentDaysBinding.wrappedValue.firstIndex(where: { $0.id == dayID }) else { return }
                    currentDaysBinding.wrappedValue[idx].exercises.append(ProgramExercise(exerciseName: exercise.name, targetSets: 3, targetReps: 8, targetWeightKg: WeightUnit.kg(fromLb: 45)))
                }
            }
        }
    }

    private var canSave: Bool { (weeks[1] ?? []).contains { !$0.exercises.isEmpty } }

    private func collapsedProgram() -> ProgramTemplate {
        let defaultDays = weeks[1] ?? []
        var overrides: [Int: [ProgramDay]] = [:]
        if weekCount >= 2 {
            for week in 2...weekCount {
                if let content = weeks[week], content != defaultDays {
                    overrides[week] = content
                }
            }
        }
        return ProgramTemplate(
            id: existingProgram?.id ?? UUID().uuidString, name: programName, weekCount: weekCount,
            defaultDays: defaultDays.filter { !$0.exercises.isEmpty }, weekOverrides: overrides,
            deloadEveryNWeeks: deloadEnabled ? deloadEveryNWeeks : nil
        )
    }
}

struct DayEditor: View {
    @Binding var day: ProgramDay
    var onAddExercise: () -> Void
    var onDeleteDay: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SelectAllTextField(text: $day.name, placeholder: "Day name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                if let onDeleteDay {
                    IconButton(systemName: "trash", action: onDeleteDay, size: 40)
                }
            }

            ForEach($day.exercises) { $exercise in
                ExerciseRowEditor(exercise: $exercise) {
                    day.exercises.removeAll { $0.id == exercise.id }
                } onDrop: { draggedID in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        moveExercise(id: draggedID, near: exercise.id)
                    }
                } onMoveToTop: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        moveExerciseToTop(id: exercise.id)
                    }
                } onMoveToBottom: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        moveExerciseToBottom(id: exercise.id)
                    }
                }
            }

            Button(action: onAddExercise) {
                Text("+ Add Exercise").font(ForgeType.caption).frame(maxWidth: .infinity)
                    .padding(9).foregroundStyle(ForgeColors.inkMuted)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(dash: [4, 4])))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // Feature request — "rearrange exercises under workouts," durable-program-editor side (see
    // `AppStore.moveExercise` for the session-screen equivalent). Local to this editor's own
    // `@Binding` array — no store method needed, it's just saved through the existing `onSave`.
    //
    // Bug fix — "when we move it, I want it more responsive... it should immediately go above it
    // if it's currently below, or below it if it's currently above." Same directional fix as
    // `AppStore.moveExercise(id:near:)` — see that doc comment for the full reasoning.
    private func moveExercise(id: String, near targetID: String) {
        guard id != targetID,
              let fromIndex = day.exercises.firstIndex(where: { $0.id == id }),
              let targetIndexBeforeMove = day.exercises.firstIndex(where: { $0.id == targetID }) else { return }
        let draggingDown = fromIndex < targetIndexBeforeMove
        let exercise = day.exercises.remove(at: fromIndex)
        guard let targetIndex = day.exercises.firstIndex(where: { $0.id == targetID }) else {
            day.exercises.insert(exercise, at: min(fromIndex, day.exercises.count))
            return
        }
        day.exercises.insert(exercise, at: draggingDown ? targetIndex + 1 : targetIndex)
    }

    private func moveExerciseToTop(id: String) {
        guard let index = day.exercises.firstIndex(where: { $0.id == id }), index != 0 else { return }
        let exercise = day.exercises.remove(at: index)
        day.exercises.insert(exercise, at: 0)
    }

    private func moveExerciseToBottom(id: String) {
        guard let index = day.exercises.firstIndex(where: { $0.id == id }), index != day.exercises.count - 1 else { return }
        let exercise = day.exercises.remove(at: index)
        day.exercises.append(exercise)
    }
}

private struct ExerciseRowEditor: View {
    @Binding var exercise: ProgramExercise
    var onDelete: () -> Void
    var onDrop: (String) -> Void
    var onMoveToTop: () -> Void
    var onMoveToBottom: () -> Void
    // Bug fix — "the reordering function is janky... when you drag it should have a ghost of the
    // card." Same treatment as `TrainView.ExerciseCard`'s equivalent.
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Bug fix — "give haptic feedback to denote it's ready to be moved." A previous
                // attempt used a `simultaneousGesture(DragGesture(minimumDistance: 0))` here to
                // catch touch-down, which competed with `.draggable`'s own touch recognition and
                // broke dragging entirely. `preview` is only evaluated once a drag session
                // actually starts, so firing the haptic from its `onAppear` needs nothing that can
                // conflict with the drag itself — same fix as `TrainView.ExerciseCard`.
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(ForgeColors.inkMuted).font(.system(size: 13))
                    .frame(width: 24, height: 36)
                    .contentShape(Rectangle())
                    .draggable(exercise.id) {
                        ExerciseDragPreview(name: exercise.exerciseName)
                            .onAppear { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                    }
                Text(exercise.exerciseName).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Spacer()
                // Feature request — "add a move to bottom button in the ... menu item and move to
                // top button as well."
                Menu {
                    Button(action: onMoveToTop) { Label("Move to Top", systemImage: "arrow.up.to.line") }
                    Button(action: onMoveToBottom) { Label("Move to Bottom", systemImage: "arrow.down.to.line") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(ForgeColors.inkMuted).font(.system(size: 16))
                        .frame(width: 30, height: 36)
                }
                IconButton(systemName: "xmark", action: onDelete, size: 36)
            }
            // Feature request — "allow users to edit the numbers numpad" — typed entry instead of
            // tapping a Stepper through every value, especially painful for reps/weight ranges.
            HStack {
                Text("Sets").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                Spacer()
                NumberField(value: $exercise.targetSets, range: 1...10)
            }
            HStack {
                Text("Reps").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                Spacer()
                NumberField(value: $exercise.targetReps, range: 1...30)
            }
            HStack {
                Text("Weight").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                Spacer()
                NumberField(value: Binding(
                    get: { WeightUnit.roundedLb(fromKg: exercise.targetWeightKg) },
                    set: { exercise.targetWeightKg = WeightUnit.kg(fromLb: Double($0)) }
                ), range: 0...600, suffix: "lb")
            }
        }
        .padding(10)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isDropTarget ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: isDropTarget)
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.first else { return false }
            onDrop(draggedID)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }
}

/// Feature request — numeric-keypad entry, filtering to digits only and clamping to `range` as
/// the user types, rather than a Stepper's one-tap-at-a-time increments. Clears on focus and
/// gets a keyboard "Done" button — "make the numpad entering more intuitive in all cases... I
/// don't want to have to select the number when editing the field... keep the formatting and
/// everything else as is though" — same behavior as every other numpad field in the app now,
/// grafted onto this field's existing visual style (frame/padding/corner radius unchanged).
private struct NumberField: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var suffix: String?

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                // Feature request — "increase text size of all editable number fields." Same
                // `.caption` → `.body` bump as Train's weight/reps fields.
                .font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                .frame(width: 50)
                .focused($isFocused)
                .onAppear { text = String(value) }
                .onChange(of: value) { newValue in
                    if !isFocused { text = String(newValue) }
                }
                .onChange(of: isFocused) { focused in
                    if focused {
                        text = ""
                    } else if text.isEmpty {
                        text = String(value)
                    }
                }
                .onChange(of: text) { newText in
                    let digits = newText.filter(\.isNumber)
                    if digits != newText { text = digits }
                    guard let parsed = Int(digits) else { return }
                    value = min(range.upperBound, max(range.lowerBound, parsed))
                }
            if let suffix {
                Text(suffix).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(ForgeColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Reused by Train's swap/add-exercise flow too, not just this editor.
struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var customExercises = CustomExerciseStore.shared
    var onSelect: (Exercise) -> Void
    @State private var query = ""
    @State private var addingCustomExercise = false
    // Bug fix — "edge case: when swapping and then creating a new exercise, offer the prompt to
    // apply to all weeks or swap for current week." See the `.sheet(isPresented: $addingCustomExercise, ...)`
    // modifier below for why this exists.
    @State private var dismissAfterAddingCustomExercise = false

    // Custom exercises first — if a user bothered to add one, it's probably what they're after
    // right now, and there won't be many of them next to the bundled 873.
    private var results: [Exercise] { Array((customExercises.search(query) + ExerciseLibrary.search(query)).prefix(40)) }

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundWash
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        SelectAllTextField(text: $query, placeholder: "Search exercises…")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Feature request — "users won't be able to find certain exercises."
                        // Always available, not just when a search comes up empty: a specific gym
                        // machine or variation might share a name with something already in the
                        // library.
                        Button { addingCustomExercise = true } label: {
                            Text("Can't find it? + Add your own").font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                        }
                        .buttonStyle(.plain)

                        ForEach(results) { exercise in
                            Button {
                                onSelect(exercise)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    Text(exercise.equipment ?? exercise.category).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            // Bug fix — "edge case: when swapping and then creating a new exercise, offer the
            // prompt to apply to all weeks or swap for current week." The picker's onAdd closure
            // used to call this sheet's own `dismiss()` immediately, while `AddCustomExerciseSheet`
            // (a *child* sheet presented on top of this one) was still on screen — dismissing an
            // ancestor sheet mid-presentation of a still-open descendant sheet doesn't sequence
            // properly, and silently dropped whatever presentation the caller tried to show right
            // after (here, TrainSessionView's "apply to future weeks?" alert, triggered by
            // `onSelect` a moment earlier). Closing the child sheet first (`addingCustomExercise
            // = false`) and only dismissing this one from that child's own `onDismiss` completion —
            // i.e. after it has actually finished closing — fixes the ordering.
            .sheet(isPresented: $addingCustomExercise, onDismiss: {
                if dismissAfterAddingCustomExercise {
                    dismissAfterAddingCustomExercise = false
                    dismiss()
                }
            }) {
                AddCustomExerciseSheet(startingName: query) { exercise in
                    onSelect(exercise)
                    dismissAfterAddingCustomExercise = true
                    addingCustomExercise = false
                }
            }
        }
    }
}

private struct AddCustomExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    var startingName: String
    var onAdd: (Exercise) -> Void

    @State private var name: String
    @State private var equipment: String = ""

    init(startingName: String, onAdd: @escaping (Exercise) -> Void) {
        self.startingName = startingName
        self.onAdd = onAdd
        _name = State(initialValue: startingName)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            Text("Add your own exercise").font(ForgeType.title).foregroundStyle(ForgeColors.ink)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                SelectAllTextField(text: $name, placeholder: "e.g. Hack Squat Machine")
                    .frame(maxWidth: .infinity)
                    .padding(10).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Equipment (optional)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                SelectAllTextField(text: $equipment, placeholder: "e.g. Machine")
                    .frame(maxWidth: .infinity)
                    .padding(10).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                let exercise = CustomExerciseStore.shared.add(name: trimmedName, equipment: equipment)
                onAdd(exercise)
            } label: {
                Text("Add Exercise").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white)
            }
            .buttonStyle(LiquidPrimaryButtonStyle())
            .disabled(trimmedName.isEmpty)
            .opacity(trimmedName.isEmpty ? 0.5 : 1)
        }
        .padding(22)
        .presentationDetents([.height(320)])
    }
}
