import SwiftUI
import ForgeCore
import PostHog

struct OnboardingView: View {
    @StateObject private var model = OnboardingViewModel()
    var onComplete: (UserProfile, ProgramTemplate) -> Void

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            VStack(alignment: .leading, spacing: 18) {
                StepDots(current: model.step, total: 4)
                Text("Step \(model.step) of 4")
                    .font(ForgeType.label)
                    .foregroundStyle(ForgeColors.accent)
                    .textCase(.uppercase)

                Group {
                    switch model.step {
                    case 1: AboutYouStep(model: model)
                    case 2: BodyActivityStep(model: model)
                    case 3: GoalStep(model: model)
                    default: ProgramSelectStep(model: model, onComplete: onComplete)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 40)
        }
    }
}

private struct StepDots: View {
    let current: Int
    let total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { n in
                Capsule()
                    .fill(n <= current ? ForgeColors.accent : ForgeColors.cardBorder)
                    .frame(width: n == current ? 22 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

private struct OptionCard: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(ForgeType.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .foregroundStyle(selected ? Color.white : ForgeColors.ink)
                .background { selected ? AnyView(ForgeColors.accent) : AnyView(Rectangle().fill(.ultraThinMaterial)) }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(selected ? Color.clear : ForgeColors.cardBorder)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ContinueButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ForgeType.title)
                .frame(maxWidth: .infinity)
                .padding(16)
                .foregroundStyle(enabled ? Color.white : ForgeColors.inkMuted)
                .background(enabled ? ForgeColors.accent : ForgeColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

/// Feature request — real onboarding inputs for age/sex/height, used directly by TDEECalculator's
/// Mifflin-St Jeor formula. These were previously hardcoded (178cm/30/male) at profile-build time,
/// silently feeding the wrong numbers into every calorie target from day one for anyone who wasn't
/// a 30-year-old 178cm male.
private struct AboutYouStep: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A bit about you").font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
                    Text("Feeds your baseline calorie math directly.").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Age").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    Picker("Age", selection: $model.age) {
                        ForEach(13...90, id: \.self) { age in Text("\(age)").tag(age) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sex").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    ForEach([Sex.male, .female], id: \.self) { s in
                        OptionCard(label: s.displayLabel, selected: model.sex == s) { model.sex = s }
                    }
                }

                HeightPicker(heightCm: $model.heightCm)

                ContinueButton(title: "Continue", enabled: model.canContinueFromAboutYou) {
                    model.step = 2
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 12)
        }
    }
}

private enum OnboardingHeightUnit: String, CaseIterable { case ftIn = "ft/in", cm = "cm" }
private enum OnboardingMassUnit: String, CaseIterable { case lb, kg }

/// Scrollable wheel, not a stepper — every value is directly reachable, nothing is skipped over.
private struct HeightPicker: View {
    @Binding var heightCm: Double
    @State private var unit: OnboardingHeightUnit = .ftIn

    private var totalInches: Int { Int((heightCm / 2.54).rounded()) }
    private var feetBinding: Binding<Int> {
        Binding(get: { totalInches / 12 }, set: { heightCm = Double($0 * 12 + totalInches % 12) * 2.54 })
    }
    private var inchesBinding: Binding<Int> {
        Binding(get: { totalInches % 12 }, set: { heightCm = Double((totalInches / 12) * 12 + $0) * 2.54 })
    }
    private var cmBinding: Binding<Int> {
        Binding(get: { Int(heightCm.rounded()) }, set: { heightCm = Double($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Height").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                Spacer()
                Picker("Unit", selection: $unit) {
                    ForEach(OnboardingHeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            if unit == .ftIn {
                HStack(spacing: 0) {
                    Picker("Feet", selection: feetBinding) {
                        ForEach(3...7, id: \.self) { ft in Text("\(ft) ft").tag(ft) }
                    }
                    .pickerStyle(.wheel)
                    Picker("Inches", selection: inchesBinding) {
                        ForEach(0...11, id: \.self) { inch in Text("\(inch) in").tag(inch) }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 110)
            } else {
                Picker("Height (cm)", selection: cmBinding) {
                    ForEach(120...220, id: \.self) { cm in Text("\(cm) cm").tag(cm) }
                }
                .pickerStyle(.wheel)
                .frame(height: 110)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Scrollable wheel, not a stepper — every value is directly reachable, nothing is skipped over.
private struct WeightPicker: View {
    var title: String = "Body weight"
    @Binding var weightLb: Double
    @State private var unit: OnboardingMassUnit = .lb

    private var lbBinding: Binding<Int> {
        Binding(get: { Int(weightLb.rounded()) }, set: { weightLb = Double($0) })
    }
    private var kgBinding: Binding<Int> {
        Binding(get: { Int((weightLb * 0.45359237).rounded()) }, set: { weightLb = Double($0) / 0.45359237 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                Spacer()
                Picker("Unit", selection: $unit) {
                    ForEach(OnboardingMassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            if unit == .lb {
                Picker("Weight (lb)", selection: lbBinding) {
                    ForEach(70...400, id: \.self) { lb in Text("\(lb) lb").tag(lb) }
                }
                .pickerStyle(.wheel)
                .frame(height: 110)
            } else {
                Picker("Weight (kg)", selection: kgBinding) {
                    ForEach(30...180, id: \.self) { kg in Text("\(kg) kg").tag(kg) }
                }
                .pickerStyle(.wheel)
                .frame(height: 110)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct BodyActivityStep: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Weight & activity").font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)

                WeightPicker(weightLb: $model.weightLb)

                Text("Activity level").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                ForEach([ActivityLevel.low, .moderate, .high], id: \.self) { level in
                    OptionCard(label: level.displayLabel, selected: model.activityLevel == level) {
                        model.activityLevel = level
                    }
                }

                ContinueButton(title: "Continue", enabled: model.activityLevel != nil) {
                    model.step = 3
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 12)
        }
    }
}

private struct GoalStep: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("What's your goal?").font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
                ForEach([Goal.cut, .bulk, .recomp, .maintain], id: \.self) { g in
                    OptionCard(label: g.displayLabel, selected: model.goal == g) { model.goal = g }
                }

                // Feature request — "add in a section asking them about their target weight and
                // time period... use those to calculate their daily caloric intake." Only shown
                // for cut/bulk — maintain/recomp don't have a literal weight target, so they keep
                // the existing fixed 0% adjustment untouched.
                if model.goal == .cut || model.goal == .bulk {
                    WeightPicker(title: "Target weight", weightLb: Binding(
                        get: { model.targetWeightLb ?? model.weightLb },
                        set: { model.targetWeightLb = $0 }
                    ))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Time period").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        Picker("Weeks", selection: $model.targetWeeks) {
                            ForEach(1...104, id: \.self) { w in Text("\(w) weeks").tag(w) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 110)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("This sets your daily calorie target — it won't change unless you update your goal or target here again.")
                        .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }

                ContinueButton(title: "Continue", enabled: model.canContinueFromGoal) {
                    model.step = 4
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 12)
        }
    }
}

private struct ProgramSelectStep: View {
    @ObservedObject var model: OnboardingViewModel
    var onComplete: (UserProfile, ProgramTemplate) -> Void
    @State private var buildingCustomProgram = false
    @State private var customProgram: ProgramTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your program").font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
            Text("Sets both your training plan and baseline target.")
                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(OnboardingViewModel.templates) { program in
                        Button {
                            model.selectedProgram = program
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(program.name).font(ForgeType.body)
                                Text(program.meta).font(ForgeType.caption)
                                    .foregroundStyle(model.selectedProgram == program ? .white.opacity(0.85) : ForgeColors.inkMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .foregroundStyle(model.selectedProgram == program ? .white : ForgeColors.ink)
                            .background {
                                model.selectedProgram == program
                                    ? AnyView(ForgeColors.accent)
                                    : AnyView(Rectangle().fill(.ultraThinMaterial))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if let customProgram {
                        Button {
                            model.selectedProgram = customProgram
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(customProgram.name).font(ForgeType.body)
                                Text(customProgram.meta).font(ForgeType.caption)
                                    .foregroundStyle(model.selectedProgram == customProgram ? .white.opacity(0.85) : ForgeColors.inkMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .foregroundStyle(model.selectedProgram == customProgram ? .white : ForgeColors.ink)
                            .background {
                                model.selectedProgram == customProgram
                                    ? AnyView(ForgeColors.accent)
                                    : AnyView(Rectangle().fill(.ultraThinMaterial))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    DashedActionButton(title: "+ Build custom program") { buildingCustomProgram = true }
                }
            }
            .sheet(isPresented: $buildingCustomProgram) {
                ProgramEditorView { program in
                    customProgram = program
                    model.selectedProgram = program
                }
            }

            ContinueButton(title: "Enter App", enabled: model.canEnterApp) {
                guard let profile = model.buildProfile(),
                      let program = model.selectedProgram else { return }
                // Goal 05 (PRD): per-feature engagement signal for the free-first paywall decision.
                PostHogSDK.shared.capture("onboarding_completed", properties: [
                    "program_id": program.id,
                    "program_name": program.name,
                    "goal": model.goal?.displayLabel ?? "unknown",
                ])
                onComplete(profile, program)
            }
        }
    }
}
