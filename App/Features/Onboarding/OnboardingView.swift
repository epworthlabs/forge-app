import SwiftUI
import ForgeCore

struct OnboardingView: View {
    @StateObject private var model = OnboardingViewModel()
    var onComplete: (UserProfile, ProgramTemplate) -> Void

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                StepDots(current: model.step, total: 4)
                Text("Step \(model.step) of 4")
                    .font(ForgeType.label)
                    .foregroundStyle(ForgeColors.accent)
                    .textCase(.uppercase)

                Group {
                    switch model.step {
                    case 1: BodyActivityStep(model: model)
                    case 2: GoalStep(model: model)
                    case 3: TrainingDaysStep(model: model)
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

private struct BodyActivityStep: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A few basics").font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)

            VStack(alignment: .leading, spacing: 10) {
                Text("Body weight").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                HStack {
                    StepperButton(symbol: "minus") { model.adjustWeight(by: -5) }
                    Spacer()
                    Text("\(Int(model.weightLb)) lb").font(ForgeType.title)
                    Spacer()
                    StepperButton(symbol: "plus") { model.adjustWeight(by: 5) }
                }
            }
            .padding(18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("Activity level").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            ForEach([ActivityLevel.low, .moderate, .high], id: \.self) { level in
                OptionCard(label: level.displayLabel, selected: model.activityLevel == level) {
                    model.activityLevel = level
                }
            }

            Spacer()
            ContinueButton(title: "Continue", enabled: model.activityLevel != nil) {
                model.step = 2
            }
        }
    }
}

private struct StepperButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 38, height: 38)
                .background(ForgeColors.tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct GoalStep: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What's your goal?").font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
            ForEach([Goal.cut, .bulk, .recomp, .maintain], id: \.self) { g in
                OptionCard(label: g.displayLabel, selected: model.goal == g) { model.goal = g }
            }
            Spacer()
            ContinueButton(title: "Continue", enabled: model.canContinueFromGoal) {
                model.step = 3
            }
        }
    }
}

private struct TrainingDaysStep: View {
    @ObservedObject var model: OnboardingViewModel
    let columns = [GridItem(.adaptive(minimum: 52))]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Training days per week?").font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(2...6, id: \.self) { n in
                    Button {
                        model.trainingDaysPerWeek = n
                    } label: {
                        Text("\(n)")
                            .font(ForgeType.title)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(model.trainingDaysPerWeek == n ? .white : ForgeColors.ink)
                            .background {
                                model.trainingDaysPerWeek == n
                                    ? AnyView(ForgeColors.accent)
                                    : AnyView(Rectangle().fill(.ultraThinMaterial))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            ContinueButton(title: "Continue", enabled: model.trainingDaysPerWeek != nil) {
                model.step = 4
            }
        }
    }
}

private struct ProgramSelectStep: View {
    @ObservedObject var model: OnboardingViewModel
    var onComplete: (UserProfile, ProgramTemplate) -> Void

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
                }
            }

            ContinueButton(title: "Enter App", enabled: model.canEnterApp) {
                // Height/age/sex placeholders here until a body-details step exists — tracked in FRG-101.
                guard let profile = model.buildProfile(heightCm: 178, age: 30, sex: .male),
                      let program = model.selectedProgram else { return }
                onComplete(profile, program)
            }
        }
    }
}
