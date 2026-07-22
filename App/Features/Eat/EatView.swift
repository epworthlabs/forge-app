import SwiftUI

struct EatView: View {
    @EnvironmentObject var store: AppStore
    @State private var searchingMeal: Meal?
    @State private var collapsedMeals: Set<Meal> = []

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
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
                                    HStack(spacing: 8) {
                                        Image(systemName: "chevron.right")
                                            .font(.body).foregroundStyle(ForgeColors.inkMuted)
                                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                                        Text(meal.rawValue).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                        if !entries.isEmpty {
                                            Text("\(entries.reduce(0) { $0 + $1.kcal }) kcal")
                                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                        }
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button("+ Add") { searchingMeal = meal }
                                    .font(ForgeType.body).foregroundStyle(ForgeColors.accent)
                                    .padding(.horizontal, 10).frame(minHeight: 44)
                            }
                            if !isCollapsed {
                                ForEach(entries) { entry in
                                    FoodEntryRow(meal: meal, entry: entry)
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

/// Feature request — "the foods logged also need to be editable and deletable. to delete, lets
/// make it a swipe left action on the food item but also offer an icon to delete." No native
/// `List` in this screen (everything else is a plain `ScrollView`, styled for the app's "Liquid
/// Glass" look, and nesting a `List` for `.swipeActions` inside that ScrollView fights SwiftUI's
/// sizing rather than working with it) — so the swipe is a small hand-rolled drag gesture instead,
/// revealing a delete button behind the row. Tapping the row (when not swiped open) edits it;
/// tapping the trash icon or the revealed swipe button both delete directly, no confirmation
/// needed since it's a single quick undo-by-re-adding action, not a destructive multi-item wipe.
private struct FoodEntryRow: View {
    @EnvironmentObject var store: AppStore
    let meal: Meal
    let entry: FoodEntry
    @State private var offset: CGFloat = 0
    @State private var editing = false

    private let revealWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.removeFoodEntry(id: entry.id, from: meal) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                FoodMonogram(name: entry.name).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                    Text("\(entry.proteinG)g P · \(entry.carbG)g C · \(entry.fatG)g F")
                        .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }
                Spacer()
                Text("\(entry.kcal)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.removeFoodEntry(id: entry.id, from: meal) }
                } label: {
                    Image(systemName: "trash").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            // Deliberately opaque, not the shared translucent `tileBackground` used elsewhere —
            // this needs to fully hide the delete button behind it until actually swiped, which a
            // "Liquid Glass" frosted/translucent fill can't do (confirmed live: tileBackground is
            // 50%/8% alpha, so the red bled straight through even at rest).
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                if offset != 0 {
                    withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                } else {
                    editing = true
                }
            }
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        let translation = value.translation.width
                        guard translation < 0 || offset < 0 else { return }
                        offset = max(translation + min(offset, 0), -revealWidth)
                    }
                    .onEnded { value in
                        withAnimation(.easeOut(duration: 0.2)) {
                            offset = value.translation.width < -revealWidth / 2 ? -revealWidth : 0
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .sheet(isPresented: $editing) {
            FoodEntryEditSheet(meal: meal, entry: entry)
        }
    }
}

/// Direct numeric edit of an already-logged entry's final values — `FoodEntry` only stores the
/// resolved macros, not the original food-database item or portion multiplier that produced them,
/// so there's nothing to reopen a portion-scaling flow against. Editing the numbers directly is
/// the honest match for what's actually stored.
private struct FoodEntryEditSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let entry: FoodEntry

    @State private var name: String
    @State private var kcal: Int
    @State private var proteinG: Int
    @State private var carbG: Int
    @State private var fatG: Int

    init(meal: Meal, entry: FoodEntry) {
        self.meal = meal
        self.entry = entry
        _name = State(initialValue: entry.name)
        _kcal = State(initialValue: entry.kcal)
        _proteinG = State(initialValue: entry.proteinG)
        _carbG = State(initialValue: entry.carbG)
        _fatG = State(initialValue: entry.fatG)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)

            Text("Edit Food").font(ForgeType.title).foregroundStyle(ForgeColors.ink)

            TextField("Name", text: $name)
                .font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                .padding(12)
                .background(ForgeColors.tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Text("Calories").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Spacer()
                NumpadField(value: $kcal, maxDigits: 4, range: 0...9999)
            }
            HStack {
                Text("Protein").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Spacer()
                NumpadField(value: $proteinG, maxDigits: 3, range: 0...999, suffix: "g")
            }
            HStack {
                Text("Carbs").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Spacer()
                NumpadField(value: $carbG, maxDigits: 3, range: 0...999, suffix: "g")
            }
            HStack {
                Text("Fat").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Spacer()
                NumpadField(value: $fatG, maxDigits: 3, range: 0...999, suffix: "g")
            }

            Button {
                store.updateFoodEntry(id: entry.id, in: meal, name: name, kcal: kcal, proteinG: proteinG, carbG: carbG, fatG: fatG)
                dismiss()
            } label: {
                Text("Save").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(22)
        .presentationDetents([.medium])
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
