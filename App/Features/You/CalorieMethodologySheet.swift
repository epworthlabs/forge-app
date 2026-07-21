import SwiftUI

/// Feature request — "documentation on the you tab explaining how everything is calculated."
/// Static methodology walkthrough, distinct from TargetExplanationSheet (which shows today's
/// actual numbers plugged into this same pipeline) — this is the "how" once, not the "why today."
struct CalorieMethodologySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Your calorie target is built in layers, each one adjusting the number the layer before it produced. Nothing here is guessed — every step is a fixed formula or a value you can see move over time.")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)

                        MethodologySection(
                            step: "1", title: "Maintenance calories (BMR × activity)",
                            body: "Your Basal Metabolic Rate — calories burned at total rest — comes from the Mifflin-St Jeor equation, using the weight, height, age, and sex you entered during onboarding. That's multiplied by your activity level (low ×1.2, moderate ×1.375, high ×1.55) to get maintenance calories: what keeps your weight stable given your day-to-day activity, before training or goals factor in."
                        )
                        MethodologySection(
                            step: "2", title: "Goal adjustment",
                            body: "Maintenance is adjusted for your stated goal: cut −20%, bulk +12.5%, maintain/recomp unchanged. This is the baseline the rest of the app works from."
                        )
                        MethodologySection(
                            step: "3", title: "Weekly trend recalibration",
                            body: "Formulas are estimates — your real metabolism might run faster or slower than Mifflin-St Jeor predicts. Once you've logged 4+ weigh-ins over 14 days, Forge compares how fast you're actually gaining or losing against how fast your goal adjustment implies you should be, and nudges the baseline to close that gap. It won't kick in on noisy, short weigh-in histories, and each correction is dampened rather than applied all at once."
                        )
                        MethodologySection(
                            step: "4", title: "Today's Load Score",
                            body: "Your target flexes day to day with training load — a heavier-than-usual week raises it, a light or missed week lowers it, measured against your own trailing average (not a fixed number). This swing is capped at ±25% of your baseline in either direction, so no single day can swing wildly."
                        )
                        MethodologySection(
                            step: "5", title: "Sleep adjustment",
                            body: "If Apple Health sync is on and last night was under 7 hours, an already-elevated Load Score gets pulled back — recovery matters as much as fuel. This only ever softens an increase; it never adds calories to compensate for poor sleep."
                        )
                        MethodologySection(
                            step: "6", title: "Safety floor",
                            body: "Your target can never imply eating below 30 kcal per kg of estimated fat-free mass, regardless of how the math above adds up. This only ever engages as a brake during an aggressive cut — it's a floor, not a target."
                        )
                        MethodologySection(
                            step: "7", title: "Protein, carbs, and fat",
                            body: "Protein is fixed by your goal (2.4g/kg on a cut, 1.7g/kg otherwise) and never moves with Load Score. Fat has a floor (0.55g/kg) for hormonal health. Carbs are what's left — they get more room on heavier training days and compress first if the calorie budget gets tight, but protein and the fat floor are never sacrificed to make room for them."
                        )

                        Text("See \"Why did my target change?\" on the Today tab for today's actual numbers run through this same pipeline.")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            .padding(.top, 4)
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("How your numbers work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct MethodologySection: View {
    let step: String
    let title: String
    let body_: String

    init(step: String, title: String, body: String) {
        self.step = step
        self.title = title
        self.body_ = body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(step).font(ForgeType.label).foregroundStyle(ForgeColors.accent)
                Text(title).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
            }
            Text(body_).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                .padding(.leading, 20)
        }
    }
}
