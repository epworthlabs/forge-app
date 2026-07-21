import SwiftUI
import ForgeCore

struct TodayView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedTab: MainTab

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Date(), style: .date).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            Text("Today").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                        }
                        Spacer()
                        Circle()
                            .fill(ForgeColors.avatarBackground)
                            .overlay(Circle().strokeBorder(ForgeColors.avatarBorder, lineWidth: 1))
                            .background(.ultraThinMaterial, in: Circle())
                            .frame(width: 38, height: 38)
                    }

                    let target = store.nutritionTarget
                    let totals = store.totals()

                    Button { store.sheetPresented = true } label: {
                        GlassCard(cornerRadius: 28) {
                            VStack(alignment: .leading, spacing: 0) {
                                if target.calorieAdjustment != 0 {
                                    HStack(spacing: 8) {
                                        Circle().fill(ForgeColors.accent).frame(width: 7, height: 7)
                                        Text("Adjusted for today's training")
                                            .font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                                    }
                                    .padding(.bottom, 10)
                                } else {
                                    Text("NUTRITION TARGET").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                        .padding(.bottom, 10)
                                }

                                HStack(spacing: 12) {
                                    LiquidTile(label: "Calories", value: "\(Int(target.calories))",
                                               delta: target.calorieAdjustment != 0 ? signedInt(target.calorieAdjustment) + " today" : nil)
                                    LiquidTile(label: "Protein", value: "\(Int(target.proteinG))g")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    if store.hasTrainingHistory {
                        HStack(spacing: 14) {
                            let doneSets = store.todaysExercises.flatMap(\.sets).filter(\.done).count
                            let totalSets = store.todaysExercises.flatMap(\.sets).count
                            RingStat(label: "Sets logged", value: "\(doneSets)/\(totalSets)",
                                     progress: totalSets > 0 ? Double(doneSets) / Double(totalSets) : 0, color: ForgeColors.accent)
                            RingStat(label: "kcal eaten", value: "\(totals.kcal)",
                                     progress: target.calories > 0 ? min(1.0, Double(totals.kcal) / target.calories) : 0, color: ForgeColors.accent2)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Macros").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            LiquidMacroRow(label: "Protein", current: totals.protein, target: Int(target.proteinG), color: ForgeColors.accent)
                            LiquidMacroRow(label: "Carbs", current: totals.carb, target: Int(target.carbG), color: ForgeColors.accent2)
                            LiquidMacroRow(label: "Fat", current: totals.fat, target: Int(target.fatG), color: ForgeColors.accent3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.currentProgramDayName).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            Text(store.todaysExercises.map(\.exercise.name).joined(separator: " · "))
                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted).lineLimit(1)
                            Button { selectedTab = .train } label: {
                                Text("Start Workout").font(ForgeType.title).frame(maxWidth: .infinity)
                                    .padding(13).foregroundStyle(Color.white).background(ForgeColors.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        DashedActionButton(title: "+ Log food") { selectedTab = .eat }
                        DashedActionButton(title: "+ Log weight") { selectedTab = .progress }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $store.sheetPresented) { TargetExplanationSheet() }
    }

    private func signedInt(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value))"
    }
}
