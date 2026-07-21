import SwiftUI
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

    init(existingProgram: ProgramTemplate? = nil, onSave: @escaping (ProgramTemplate) -> Void) {
        self.existingProgram = existingProgram
        self.onSave = onSave
        _programName = State(initialValue: existingProgram?.name ?? "My Program")
        _weekCount = State(initialValue: existingProgram?.weekCount ?? 8)
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
                ForgeColors.backgroundBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Program name", text: $programName)
                            .font(ForgeType.title).foregroundStyle(ForgeColors.ink)
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
                                .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                    }
                    .padding(20)
                }
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
            deloadEveryNWeeks: existingProgram?.deloadEveryNWeeks
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
                TextField("Day name", text: $day.name)
                    .font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Spacer()
                if let onDeleteDay {
                    Button(action: onDeleteDay) {
                        Image(systemName: "trash").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach($day.exercises) { $exercise in
                ExerciseRowEditor(exercise: $exercise) {
                    day.exercises.removeAll { $0.id == exercise.id }
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
}

private struct ExerciseRowEditor: View {
    @Binding var exercise: ProgramExercise
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exercise.exerciseName).font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                }
                .buttonStyle(.plain)
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
    }
}

/// Feature request — numeric-keypad entry, filtering to digits only and clamping to `range` as
/// the user types, rather than a Stepper's one-tap-at-a-time increments.
private struct NumberField: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var suffix: String?

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: Binding(
                get: { String(value) },
                set: { newText in
                    let digits = newText.filter(\.isNumber)
                    let parsed = Int(digits) ?? range.lowerBound
                    value = min(range.upperBound, max(range.lowerBound, parsed))
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
            .frame(width: 44)
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

    // Custom exercises first — if a user bothered to add one, it's probably what they're after
    // right now, and there won't be many of them next to the bundled 873.
    private var results: [Exercise] { Array((customExercises.search(query) + ExerciseLibrary.search(query)).prefix(40)) }

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Search exercises…", text: $query)
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
            .sheet(isPresented: $addingCustomExercise) {
                AddCustomExerciseSheet(startingName: query) { exercise in
                    onSelect(exercise)
                    dismiss()
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
                TextField("e.g. Hack Squat Machine", text: $name)
                    .padding(10).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Equipment (optional)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                TextField("e.g. Machine", text: $equipment)
                    .padding(10).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                let exercise = CustomExerciseStore.shared.add(name: trimmedName, equipment: equipment)
                onAdd(exercise)
            } label: {
                Text("Add Exercise").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(trimmedName.isEmpty)
            .opacity(trimmedName.isEmpty ? 0.5 : 1)
        }
        .padding(22)
        .presentationDetents([.height(320)])
    }
}
