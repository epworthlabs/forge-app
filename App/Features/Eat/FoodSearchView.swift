import SwiftUI
import ForgeCore

/// Quantity unit for a logged portion — shared between the initial "how much did you eat" flow
/// (`PortionConfirmSheet`, below) and editing an already-logged entry's serving size (`EatView`'s
/// `FoodEntryEditSheet`), so both reuse the exact same scaling math and can't drift apart.
enum PortionUnit: String, CaseIterable, Codable {
    case g = "g", oz = "oz", servings = "servings"
}

enum PortionScaling {
    static func multiplier(quantity: Double, unit: PortionUnit, referenceGrams: Double?) -> Double {
        guard quantity >= 0 else { return 0 }
        switch unit {
        case .g: return referenceGrams.map { quantity / $0 } ?? 0
        case .oz: return referenceGrams.map { (quantity * 28.3495) / $0 } ?? 0
        case .servings: return quantity
        }
    }
}

struct FoodSearchView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meal: Meal

    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var isSearching = false
    @State private var confirmingFood: FoodSearchResult?

    // Feature request — "make searching for food items even more robust." Rendering every result
    // eagerly in a plain VStack meant a broad query laid out hundreds of rows at once; capping to
    // the top matches (already ranked by FoodSearchService) plus a lazy container keeps a heavy
    // query from stalling the scroll view.
    private let maxDisplayedResults = 40

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundWash
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        TextField("Search…", text: $query)
                            .font(ForgeType.body)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if query.isEmpty {
                            // Feature request — "let users see a list of favourite foods whenever
                            // they go to add to their meals... similar to the recent items."
                            // Long-press to remove is how the list gets "edited" — mirrors the
                            // existing recents row exactly, just with one added affordance.
                            if !store.favoriteFoods.isEmpty {
                                Text("FAVORITES").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(store.favoriteFoods) { food in
                                            Button { confirmingFood = food } label: {
                                                Text(food.name).font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
                                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                                    .background(.ultraThinMaterial)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .contextMenu {
                                                Button("Remove from Favorites", role: .destructive) {
                                                    store.toggleFavoriteFood(food)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            if !store.recentFoods.isEmpty {
                                Text("RECENT & FREQUENT").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(store.recentFoods) { food in
                                            Button {
                                                confirmingFood = food
                                            } label: {
                                                Text(food.name).font(ForgeType.caption).foregroundStyle(ForgeColors.ink)
                                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                                    .background(.ultraThinMaterial)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        Text("RESULTS").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)

                        if isSearching {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                        } else if results.isEmpty && !query.isEmpty {
                            Text("No results for \"\(query)\"").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }

                        ForEach(results.prefix(maxDisplayedResults)) { food in
                            HStack(spacing: 10) {
                                Button {
                                    confirmingFood = food
                                } label: {
                                    HStack(spacing: 10) {
                                        FoodMonogram(name: food.name).frame(width: 32, height: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Text(food.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                                if let brand = food.brand {
                                                    Text("· \(brand)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                                }
                                            }
                                            Text("\(Int(food.proteinG))g P · \(Int(food.carbG))g C · \(Int(food.fatG))g F · \(food.servingDescription)")
                                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                        }
                                        Spacer()
                                        Text("\(food.kcal)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    store.toggleFavoriteFood(food)
                                } label: {
                                    Image(systemName: store.isFavoriteFood(food) ? "star.fill" : "star")
                                        .foregroundStyle(store.isFavoriteFood(food) ? ForgeColors.accent : ForgeColors.inkMuted)
                                        .font(.body)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Text("USDA FDC · Open Food Facts · FatSecret")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            .frame(maxWidth: .infinity).padding(.top, 12)
                    }
                    .padding(20)
                }
                .dismissKeyboardOnTap()
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Add to \(meal.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350)) // debounce — cancelled by .task(id:) on each keystroke
            guard !Task.isCancelled else { return }
            isSearching = true
            results = await store.foodSearchService.search(query: query)
            isSearching = false
        }
        .sheet(item: $confirmingFood) { food in
            PortionConfirmSheet(food: food, meal: meal) { originalFood, quantity, unit, referenceGrams in
                store.logFood(originalFood, quantity: quantity, unit: unit, referenceGrams: referenceGrams, to: meal)
                dismiss()
            }
        }
    }
}

/// Feature request — quantity typed freely in whichever unit the user has on hand (grams, ounces,
/// or a plain serving count), rather than locked to 0.25x steps of the reported serving size.
/// Grams/ounces only appear as options when `referenceGrams` can actually be parsed from the
/// food's serving description — without that there's nothing to scale a gram entry against, so
/// the sheet falls back to servings-only (still freely typed, just not a fixed step).
private struct PortionConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let food: FoodSearchResult
    let meal: Meal
    var onConfirm: (FoodSearchResult, Double, PortionUnit, Double?) -> Void

    private let referenceGrams: Double?
    @State private var unit: PortionUnit
    @State private var quantityText: String
    @FocusState private var quantityFocused: Bool
    @State private var quantityBeforeFocus: String = ""

    init(food: FoodSearchResult, meal: Meal, onConfirm: @escaping (FoodSearchResult, Double, PortionUnit, Double?) -> Void) {
        self.food = food
        self.meal = meal
        self.onConfirm = onConfirm
        let grams = food.referenceGrams
        referenceGrams = grams
        _unit = State(initialValue: grams != nil ? .g : .servings)
        _quantityText = State(initialValue: grams != nil ? Self.trimmedDecimal(grams!) : "1")
    }

    private var availableUnits: [PortionUnit] { referenceGrams != nil ? [.g, .oz, .servings] : [.servings] }

    private var quantity: Double { Double(quantityText) ?? 0 }
    private var multiplier: Double { PortionScaling.multiplier(quantity: quantity, unit: unit, referenceGrams: referenceGrams) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(ForgeType.title).foregroundStyle(ForgeColors.ink)
                if let brand = food.brand {
                    Text(brand).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Reported as \(food.servingDescription)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                HStack(spacing: 10) {
                    TextField("Amount", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .font(ForgeType.title)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(width: 90)
                        .background(ForgeColors.tileBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .focused($quantityFocused)
                        // "Make the numpad entering more intuitive in all cases... I don't want
                        // to have to select the number when editing the field" — same
                        // clear-on-focus treatment as every other numeric field in the app.
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
                }
            }

            HStack(spacing: 10) {
                PortionMacroTile(label: "kcal", value: "\(scaledKcal)")
                PortionMacroTile(label: "Protein", value: "\(Int(scaledProtein.rounded()))g")
                PortionMacroTile(label: "Carbs", value: "\(Int(scaledCarb.rounded()))g")
                PortionMacroTile(label: "Fat", value: "\(Int(scaledFat.rounded()))g")
            }

            Button {
                onConfirm(food, quantity, unit, referenceGrams)
            } label: {
                Text("Add to \(meal.rawValue)").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(multiplier <= 0)
            .opacity(multiplier <= 0 ? 0.5 : 1)
        }
        .padding(22)
        .presentationDetents([.height(400)])
        .dismissKeyboardOnTap()
    }

    private var scaledKcal: Int { Int((Double(food.kcal) * multiplier).rounded()) }
    private var scaledProtein: Double { food.proteinG * multiplier }
    private var scaledCarb: Double { food.carbG * multiplier }
    private var scaledFat: Double { food.fatG * multiplier }

    private static func trimmedDecimal(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

struct PortionMacroTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
