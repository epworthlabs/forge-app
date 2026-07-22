import SwiftUI

struct EatView: View {
    @EnvironmentObject var store: AppStore
    @State private var searchingMeal: Meal?
    @State private var collapsedMeals: Set<Meal> = []

    // Feature request — "allow users to go back and view their food logs from previous days."
    // 0 = today (the live, fully-editable in-memory state everything else already used); anything
    // else is a read-only historical snapshot fetched from CloudKit — logging/editing/deleting stays
    // scoped to today, since past days are for review, not retroactive editing.
    @State private var dayOffset = 0
    @State private var historicalEntries: [Meal: [FoodEntry]]?

    private var viewingDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }
    private var isToday: Bool { dayOffset == 0 }

    private var displayedEntries: [Meal: [FoodEntry]] {
        isToday ? store.mealEntries : (historicalEntries ?? [:])
    }

    private var displayedTotals: (kcal: Int, protein: Int, carb: Int, fat: Int) {
        guard !isToday else { return store.totals() }
        let entries = Meal.allCases.flatMap { displayedEntries[$0] ?? [] }
        return (entries.reduce(0) { $0 + $1.kcal }, entries.reduce(0) { $0 + $1.proteinG },
                entries.reduce(0) { $0 + $1.carbG }, entries.reduce(0) { $0 + $1.fatG })
    }

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Eat").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        IconButton(systemName: "chevron.left", action: { dayOffset -= 1 }, size: 32)
                        Text(isToday ? "Today" : Self.dateLabel(viewingDate))
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            .frame(maxWidth: .infinity)
                        IconButton(systemName: "chevron.right", action: { dayOffset += 1 }, size: 32)
                            .disabled(isToday)
                            .opacity(isToday ? 0.4 : 1)
                    }

                    let target = store.nutritionTarget
                    let totals = displayedTotals
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(isToday ? "REMAINING" : "LOGGED").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                Spacer()
                                Text(isToday ? "\(max(0, Int(target.calories) - totals.kcal)) kcal" : "\(totals.kcal) kcal")
                                    .font(ForgeType.title).foregroundStyle(ForgeColors.ink)
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
                        let entries = displayedEntries[meal] ?? []
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
                                if isToday {
                                    Button("+ Add") { searchingMeal = meal }
                                        .font(ForgeType.body).foregroundStyle(ForgeColors.accent)
                                        .padding(.horizontal, 10).frame(minHeight: 44)
                                }
                            }
                            if !isCollapsed {
                                ForEach(entries) { entry in
                                    if isToday {
                                        FoodEntryRow(meal: meal, entry: entry)
                                    } else {
                                        ReadOnlyFoodEntryRow(entry: entry)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .task(id: dayOffset) {
            guard !isToday else { historicalEntries = nil; return }
            let start = Calendar.current.startOfDay(for: viewingDate)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? viewingDate
            historicalEntries = try? await CloudKitStore.shared.fetchFoodEntries(from: start, to: end)
        }
        .sheet(item: $searchingMeal) { meal in
            FoodSearchView(meal: meal)
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}

/// Read-only row for a past day's entry — no swipe-to-delete, no tap-to-edit, since browsing
/// history isn't an editing surface (only today's diary is).
private struct ReadOnlyFoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: 10) {
            FoodMonogram(name: entry.name).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Text("\(entry.proteinG)g P · \(entry.carbG)g C · \(entry.fatG)g F")
                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
            Spacer()
            Text("\(entry.kcal)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Feature request — "get rid of the swipe and delete function, doesn't add any value when there's
/// an icon to delete." The hand-rolled swipe-to-reveal gesture (FRG-358) is gone; the always-
/// visible trash icon is the sole delete affordance now. Tapping the row itself opens the edit sheet.
private struct FoodEntryRow: View {
    @EnvironmentObject var store: AppStore
    let meal: Meal
    let entry: FoodEntry
    @State private var editing = false

    var body: some View {
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
        .background(ForgeColors.tileBackground)
        .contentShape(Rectangle())
        .onTapGesture { editing = true }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .sheet(isPresented: $editing) {
            FoodEntryEditSheet(meal: meal, entry: entry)
        }
    }
}

/// Feature request — "scrap the current editing flow for when users go into edit specific meals.
/// Can we give them the ability to edit their serving quantity whether it be in g, oz, or # of
/// servings? After editing that, the macros and calories should update automatically." Replaces
/// the old raw-numeric macro editor (FRG-358) with the same quantity+unit scaling
/// `PortionConfirmSheet` uses when a food is first logged — editing the serving size recomputes
/// kcal/protein/carb/fat instead of typing them directly.
private struct FoodEntryEditSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let entry: FoodEntry

    @State private var name: String
    @State private var unit: PortionUnit
    @State private var quantityText: String
    @State private var referenceGrams: Double?
    @FocusState private var quantityFocused: Bool
    @State private var quantityBeforeFocus: String = ""

    init(meal: Meal, entry: FoodEntry) {
        self.meal = meal
        self.entry = entry
        _name = State(initialValue: entry.name)
        _unit = State(initialValue: entry.unit)
        _quantityText = State(initialValue: Self.trimmedDecimal(entry.quantity))
        _referenceGrams = State(initialValue: entry.referenceGrams)
    }

    // Bug fix — "I can't change from servings to g or oz when I edit. Make it so I can." All 3
    // units are always offered now, not just when a gram reference happens to already be known
    // (e.g. an entry originally logged in plain servings, with nothing to scale grams against, was
    // permanently stuck there). Switching to g/oz for the first time on such an entry assumes a
    // 100g reference (see the `onChange` below) so it becomes scalable immediately.
    private var availableUnits: [PortionUnit] { PortionUnit.allCases }

    private var quantity: Double { Double(quantityText) ?? 0 }
    private var multiplier: Double { PortionScaling.multiplier(quantity: quantity, unit: unit, referenceGrams: referenceGrams) }

    private var scaledKcal: Int { Int((entry.effectiveBaseKcal * multiplier).rounded()) }
    private var scaledProtein: Double { entry.effectiveBaseProteinG * multiplier }
    private var scaledCarb: Double { entry.effectiveBaseCarbG * multiplier }
    private var scaledFat: Double { entry.effectiveBaseFatG * multiplier }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)

            Text("Edit Food").font(ForgeType.title).foregroundStyle(ForgeColors.ink)

            TextField("Name", text: $name)
                .font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                .padding(12)
                .background(ForgeColors.tileBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                TextField("Amount", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .font(ForgeType.title)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(width: 90)
                    .background(ForgeColors.tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focused($quantityFocused)
                    .onChange(of: quantityFocused) { focused in
                        if focused {
                            quantityBeforeFocus = quantityText
                            quantityText = ""
                        } else if quantityText.isEmpty {
                            quantityText = quantityBeforeFocus
                        }
                    }

                Picker("Unit", selection: $unit) {
                    ForEach(availableUnits, id: \.self) { u in Text(u.rawValue).tag(u) }
                }
                .pickerStyle(.segmented)
                .onChange(of: unit) { newUnit in
                    guard newUnit != .servings, referenceGrams == nil else { return }
                    referenceGrams = 100
                    quantityText = "100"
                }
            }

            HStack(spacing: 10) {
                PortionMacroTile(label: "kcal", value: "\(scaledKcal)")
                PortionMacroTile(label: "Protein", value: "\(Int(scaledProtein.rounded()))g")
                PortionMacroTile(label: "Carbs", value: "\(Int(scaledCarb.rounded()))g")
                PortionMacroTile(label: "Fat", value: "\(Int(scaledFat.rounded()))g")
            }

            Button {
                store.updateFoodEntryPortion(id: entry.id, in: meal, name: name, quantity: quantity, unit: unit, referenceGrams: referenceGrams)
                dismiss()
            } label: {
                Text("Save").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || multiplier <= 0)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || multiplier <= 0 ? 0.5 : 1)
        }
        .padding(22)
        .presentationDetents([.medium])
        .dismissKeyboardOnTap()
    }

    private static func trimmedDecimal(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
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
