import SwiftUI

struct EatView: View {
    @EnvironmentObject var store: AppStore
    @State private var searchingMeal: Meal?
    @State private var collapsedMeals: Set<Meal> = []

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
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("REMAINING").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                Spacer()
                                Text("\(max(0, Int(target.calories) - totals.kcal)) kcal").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
                            }
                            EatMacroRow(label: "Protein", current: totals.protein, target: Int(target.proteinG))
                            EatMacroRow(label: "Carbs", current: totals.carb, target: Int(target.carbG))
                            EatMacroRow(label: "Fat", current: totals.fat, target: Int(target.fatG))

                            // Feature request — live macro split as a percentage of calories
                            // logged so far today, distinct from the target-progress bars above.
                            Divider().overlay(ForgeColors.cardBorder)
                            MacroSplitChart(proteinG: totals.protein, carbG: totals.carb, fatG: totals.fat)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(Meal.allCases) { meal in
                        let isCollapsed = collapsedMeals.contains(meal)
                        let entries = store.mealEntries[meal] ?? []
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if isCollapsed { collapsedMeals.remove(meal) } else { collapsedMeals.insert(meal) }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(ForgeColors.inkMuted)
                                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                                        Text(meal.rawValue).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                        if !entries.isEmpty {
                                            Text("\(entries.reduce(0) { $0 + $1.kcal }) kcal")
                                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button("+ Add") { searchingMeal = meal }
                                    .font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                            }
                            if !isCollapsed {
                                ForEach(entries) { entry in
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

/// Feature request — donut chart of today's logged macro split by calorie share (protein/carb
/// 4 kcal/g, fat 9 kcal/g), with % labels that update live as entries are logged. Hand-drawn via
/// Canvas rather than Swift Charts' SectorMark, which needs iOS 17 — this app's deployment target
/// is iOS 16.
private struct MacroSplitChart: View {
    let proteinG: Int
    let carbG: Int
    let fatG: Int

    private var proteinKcal: Double { Double(proteinG) * 4 }
    private var carbKcal: Double { Double(carbG) * 4 }
    private var fatKcal: Double { Double(fatG) * 9 }
    private var totalKcal: Double { proteinKcal + carbKcal + fatKcal }

    private var slices: [(color: Color, label: String, kcal: Double)] {
        [
            (ForgeColors.accent, "Protein", proteinKcal),
            (ForgeColors.accent2, "Carbs", carbKcal),
            (ForgeColors.accent3, "Fat", fatKcal),
        ]
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                if totalKcal > 0 {
                    DonutChart(values: slices.map { $0.kcal / totalKcal }, colors: slices.map(\.color))
                        .frame(width: 84, height: 84)
                } else {
                    Circle().stroke(ForgeColors.cardBorder, style: StrokeStyle(lineWidth: 12)).frame(width: 84, height: 84)
                }
                VStack(spacing: 0) {
                    Text("\(Int(totalKcal))").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                    Text("kcal").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices, id: \.label) { slice in
                    HStack(spacing: 8) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        Spacer()
                        Text(percentLabel(for: slice.kcal)).font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
                    }
                }
            }
        }
    }

    private func percentLabel(for kcal: Double) -> String {
        guard totalKcal > 0 else { return "—" }
        return "\(Int((kcal / totalKcal * 100).rounded()))%"
    }
}

private struct DonutChart: View {
    let values: [Double]
    let colors: [Color]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(size.width, size.height) / 2
            var startAngle = Angle(degrees: -90)

            context.drawLayer { layer in
                for (value, color) in zip(values, colors) where value > 0 {
                    let endAngle = startAngle + Angle(degrees: value * 360)
                    var path = Path()
                    path.move(to: center)
                    path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                    path.closeSubpath()
                    layer.fill(path, with: .color(color))
                    startAngle = endAngle
                }

                let holeRadius = radius * 0.58
                let holeRect = CGRect(x: center.x - holeRadius, y: center.y - holeRadius, width: holeRadius * 2, height: holeRadius * 2)
                layer.blendMode = .destinationOut
                layer.fill(Path(ellipseIn: holeRect), with: .color(.black))
            }
        }
    }
}
