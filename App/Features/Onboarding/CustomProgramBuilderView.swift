import SwiftUI
import ForgeCore

/// FRG-104 — lets a user build a program from scratch: name it, add days, and for each day add
/// exercises (searched from the full 873-exercise library) with sets/reps/weight. The result is a
/// plain `ProgramTemplate` — indistinguishable from a curated one past this screen, since that's
/// exactly what makes `AppStore.buildExerciseSlots` work for both without special-casing.
struct CustomProgramBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (ProgramTemplate) -> Void

    @State private var programName = "My Program"
    @State private var days: [ProgramDay] = [ProgramDay(name: "Day 1", exercises: [])]
    @State private var pickingExerciseForDayID: String?

    private var canSave: Bool { days.contains { !$0.exercises.isEmpty } }

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

                        ForEach($days) { $day in
                            DayEditor(
                                day: $day,
                                onAddExercise: { pickingExerciseForDayID = day.id },
                                onDeleteDay: days.count > 1 ? { days.removeAll { $0.id == day.id } } : nil
                            )
                        }

                        Button {
                            days.append(ProgramDay(name: "Day \(days.count + 1)", exercises: []))
                        } label: {
                            Text("+ Add Day").font(ForgeType.body).frame(maxWidth: .infinity)
                                .padding(12).foregroundStyle(ForgeColors.inkMuted)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(dash: [5, 4])))
                        }
                        .buttonStyle(.plain)

                        Button {
                            let program = ProgramTemplate(
                                id: UUID().uuidString, name: programName, weeks: 8,
                                days: days.filter { !$0.exercises.isEmpty }
                            )
                            onSave(program)
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
            .navigationTitle("Build Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: Binding(get: { pickingExerciseForDayID != nil }, set: { if !$0 { pickingExerciseForDayID = nil } })) {
                ExercisePickerSheet { exercise in
                    guard let dayID = pickingExerciseForDayID, let idx = days.firstIndex(where: { $0.id == dayID }) else { return }
                    days[idx].exercises.append(ProgramExercise(exerciseName: exercise.name, targetSets: 3, targetReps: 8, targetWeightKg: 20))
                }
            }
        }
    }
}

private struct DayEditor: View {
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
            HStack(spacing: 14) {
                Stepper("Sets: \(exercise.targetSets)", value: $exercise.targetSets, in: 1...10)
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
            HStack(spacing: 14) {
                Stepper("Reps: \(exercise.targetReps)", value: $exercise.targetReps, in: 1...30)
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
            HStack(spacing: 14) {
                Stepper("Weight: \(Int(exercise.targetWeightKg)) kg", value: $exercise.targetWeightKg, in: 0...300, step: 2.5)
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
        }
        .padding(10)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (Exercise) -> Void
    @State private var query = ""

    private var results: [Exercise] { Array(ExerciseLibrary.search(query).prefix(40)) }

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
        }
    }
}
