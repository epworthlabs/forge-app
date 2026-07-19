import SwiftUI

struct EatView: View {
    @EnvironmentObject var store: AppStore
    @State private var searchingMeal: Meal?

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Eat").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                        Spacer()
                        Text(Date(), style: .date).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    }

                    let target = store.nutritionTarget
                    let totals = store.totals()
                    GlassCard {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("REMAINING").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                Spacer()
                                Text("\(max(0, Int(target.calories) - totals.kcal)) kcal").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
                            }
                            EatMacroRow(label: "Protein", current: totals.protein, target: Int(target.proteinG))
                            EatMacroRow(label: "Carbs", current: totals.carb, target: Int(target.carbG))
                            EatMacroRow(label: "Fat", current: totals.fat, target: Int(target.fatG))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(Meal.allCases) { meal in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(meal.rawValue).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                Spacer()
                                Button("+ Add") { searchingMeal = meal }
                                    .font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                            }
                            ForEach(store.mealEntries[meal] ?? []) { entry in
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ForgeColors.tileBackground).frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                        Text("\(entry.proteinG)g P · \(entry.carbG)g C · \(entry.fatG)g F")
                                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                    Spacer()
                                    Text("\(entry.kcal)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .sheet(item: $searchingMeal) { meal in
            FoodSearchView(meal: meal)
        }
    }
}

private struct EatMacroRow: View {
    let label: String
    let current: Int
    let target: Int
    var body: some View {
        HStack {
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted).frame(width: 50, alignment: .leading)
            GeometryReader { geo in
                let pct = target > 0 ? min(1.0, Double(current) / Double(target)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgeColors.trackBackground)
                    Capsule().fill(ForgeColors.ink).frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 7)
            Text("\(current)g").font(ForgeType.caption).foregroundStyle(ForgeColors.ink).frame(width: 40, alignment: .trailing)
        }
    }
}
