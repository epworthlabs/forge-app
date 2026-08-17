import SwiftUI

/// Feature request — "documentation on the you tab explaining how everything is calculated."
/// Static methodology walkthrough, distinct from TargetExplanationSheet (which shows today's
/// actual numbers plugged into this same pipeline) — this is the "how" once, not the "why today."
///
/// App Store 1.4.1 rejection — "medical/health calculations... does not include citations." Every
/// formula below now carries an inline citation link to the source it's drawn from, plus a full
/// "Sources" list at the bottom so they're all in one place regardless of which step a user reads.
/// Reachable both from here (You tab) and directly from the Eat tab's info button, since the
/// rejection called out the meal logging feature specifically — citations shouldn't be a hunt.
struct CalorieMethodologySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundWash
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Your calorie target is built in layers, each one adjusting the number the layer before it produced. Nothing here is guessed — every step is a fixed formula or a value you can see move over time. Sources for each formula are linked below and listed together at the end.")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)

                        MethodologySection(
                            step: "1", title: "Maintenance calories (BMR × activity)",
                            body: "Your Basal Metabolic Rate — calories burned at total rest — comes from the Mifflin-St Jeor equation, using the weight, height, age, and sex you entered during onboarding. That's multiplied by your activity level (low ×1.2, moderate ×1.375, high ×1.55) to get maintenance calories: what keeps your weight stable given your day-to-day activity, before training or goals factor in.",
                            citations: [.mifflinStJeor, .activityMultiplier]
                        )
                        MethodologySection(
                            step: "2", title: "Goal adjustment",
                            body: "If you set a target weight and time period (cut or bulk), maintenance is adjusted by exactly the daily deficit or surplus that target implies — fixed until you change your goal or target in You → Goal & Target, not recalculated day to day. Without a target set, maintenance uses a flat adjustment instead: cut −20%, bulk +12.5%, maintain/recomp unchanged. Either way, this is the baseline the rest of the app works from.",
                            citations: [.energyDensity]
                        )
                        MethodologySection(
                            step: "3", title: "Weekly trend recalibration",
                            body: "Formulas are estimates — your real metabolism might run faster or slower than Mifflin-St Jeor predicts. Once you've logged 4+ weigh-ins over 14 days, Trakt compares how fast you're actually gaining or losing against how fast your goal adjustment implies you should be, and nudges the baseline to close that gap. It won't kick in on noisy, short weigh-in histories, and each correction is dampened rather than applied all at once.",
                            citations: [.energyDensity]
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
                            body: "Your target can never imply eating below 30 kcal per kg of estimated fat-free mass, regardless of how the math above adds up. This only ever engages as a brake during an aggressive cut — it's a floor, not a target.",
                            citations: [.redS]
                        )
                        MethodologySection(
                            step: "7", title: "Protein, carbs, and fat",
                            body: "Protein is fixed by your goal (2.4g/kg on a cut, 1.7g/kg otherwise) and never moves with Load Score. Fat has a floor (0.55g/kg) for hormonal health. Carbs are what's left — they get more room on heavier training days and compress first if the calorie budget gets tight, but protein and the fat floor are never sacrificed to make room for them. Gram-to-calorie conversion uses 4 kcal/g for protein and carbs, 9 kcal/g for fat.",
                            citations: [.proteinPositionStand, .atwater]
                        )

                        Text("See \"Why did my target change?\" on the Today tab for today's actual numbers run through this same pipeline.")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            .padding(.top, 4)

                        Divider().overlay(ForgeColors.cardBorder).padding(.top, 4)

                        SourcesSection()

                        Text("Trakt's targets are estimates based on general formulas, not medical advice. Talk to a doctor or registered dietitian before making significant changes to your diet, especially if you have a health condition.")
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

/// One citable source. `url` links to a stable, publicly accessible page for the underlying
/// research/guidance rather than a paywalled PDF, so it's actually reachable from the app.
struct Citation: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
    let url: URL

    static let mifflinStJeor = Citation(
        label: "Mifflin-St Jeor equation",
        detail: "Mifflin MD, St Jeor ST, et al. \"A new predictive equation for resting energy expenditure in healthy individuals.\" Am J Clin Nutr, 1990.",
        url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!
    )
    static let activityMultiplier = Citation(
        label: "Activity (PAL) multipliers",
        detail: "Institute of Medicine. \"Dietary Reference Intakes for Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino Acids,\" 2005.",
        url: URL(string: "https://nap.nationalacademies.org/catalog/10490")!
    )
    static let energyDensity = Citation(
        label: "~7,700 kcal per kg of body weight",
        detail: "Wishnofsky M. \"Caloric equivalents of gained or lost weight.\" Am J Clin Nutr, 1958.",
        url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/13611024/")!
    )
    static let proteinPositionStand = Citation(
        label: "Protein intake (g/kg) recommendations",
        detail: "Jäger R, et al. \"International Society of Sports Nutrition Position Stand: protein and exercise.\" J Int Soc Sports Nutr, 2017.",
        url: URL(string: "https://jissn.biomedcentral.com/articles/10.1186/s12970-017-0177-8")!
    )
    static let redS = Citation(
        label: "30 kcal/kg fat-free mass safety floor",
        detail: "Mountjoy M, et al. \"IOC consensus statement on Relative Energy Deficiency in Sport (RED-S).\" Br J Sports Med, 2018 update.",
        url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/29773536/")!
    )
    static let atwater = Citation(
        label: "4/4/9 kcal-per-gram macronutrient values",
        detail: "USDA. \"Energy Value of Foods: Basis and Derivation\" (Atwater system), Agriculture Handbook 74.",
        url: URL(string: "https://www.ars.usda.gov/ARSUserFiles/80400525/Data/Classics/ah74.pdf")!
    )

    static let all: [Citation] = [.mifflinStJeor, .activityMultiplier, .energyDensity, .proteinPositionStand, .redS, .atwater]
}

private struct SourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOURCES").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
            ForEach(Citation.all) { citation in
                Link(destination: citation.url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(citation.label).font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                        Text(citation.detail).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MethodologySection: View {
    let step: String
    let title: String
    let body_: String
    let citations: [Citation]

    init(step: String, title: String, body: String, citations: [Citation] = []) {
        self.step = step
        self.title = title
        self.body_ = body
        self.citations = citations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(step).font(ForgeType.label).foregroundStyle(ForgeColors.accent)
                Text(title).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
            }
            Text(body_).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                .padding(.leading, 20)
            if !citations.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(citations) { citation in
                        Link(destination: citation.url) {
                            Text("Source: \(citation.label)")
                                .font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                        }
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            }
        }
    }
}
