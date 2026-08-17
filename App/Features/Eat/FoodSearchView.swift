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

    @ObservedObject private var customFoods = CustomFoodStore.shared
    @ObservedObject private var recipes = RecipeStore.shared

    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var isSearching = false
    @State private var confirmingFood: FoodSearchResult?
    @State private var addingCustomFood = false
    @State private var buildingRecipe = false
    @State private var viewingMyRecipes = false

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
                        SelectAllTextField(text: $query, placeholder: "Search…")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Feature request — "add their own foods on their own devices" + "group a
                        // collection of foods and save + input it as a recipe." Always available,
                        // not just on an empty search.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button { addingCustomFood = true } label: {
                                    Text("+ Add Food").font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                                }
                                .buttonStyle(LiquidChipButtonStyle())
                                Button { buildingRecipe = true } label: {
                                    Text("+ Create a recipe").font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                                }
                                .buttonStyle(LiquidChipButtonStyle())
                                // Feature request — "give users a more accessible way to log their
                                // own saved recipes, they shouldn't have to search for it, it
                                // should be in a separate folder/bookmark." A direct list, not
                                // routed through the search-results merge below — only shown once
                                // there's something to browse.
                                if !recipes.recipes.isEmpty {
                                    Button { viewingMyRecipes = true } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "bookmark.fill")
                                            Text("My Recipes")
                                        }
                                        .font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                                    }
                                    .buttonStyle(LiquidChipButtonStyle())
                                }
                            }
                        }

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
            // Local-first, same merge order `ExercisePickerSheet` uses for custom exercises — a
            // user's own foods/recipes are the most likely match for what they're searching for.
            let local = customFoods.search(query) + recipes.searchAsFoodResults(query)
            let networked = await store.foodSearchService.search(query: query)
            results = local + networked
            isSearching = false
        }
        .sheet(item: $confirmingFood) { food in
            PortionConfirmSheet(food: food, confirmButtonTitle: "Add to \(meal.rawValue)") { originalFood, quantity, unit, referenceGrams in
                store.logFood(originalFood, quantity: quantity, unit: unit, referenceGrams: referenceGrams, to: meal)
                dismiss()
            }
        }
        .sheet(isPresented: $addingCustomFood) {
            AddCustomFoodSheet(startingName: query) { food in
                confirmingFood = food
            }
        }
        .sheet(isPresented: $buildingRecipe) {
            RecipeBuilderSheet { recipe in
                confirmingFood = recipe.asFoodSearchResult
            }
        }
        .sheet(isPresented: $viewingMyRecipes) {
            MyRecipesView { recipe in
                confirmingFood = recipe.asFoodSearchResult
            }
        }
    }
}

/// Feature request — quantity typed freely in whichever unit the user has on hand (grams, ounces,
/// or a plain serving count), rather than locked to 0.25x steps of the reported serving size.
/// Grams/ounces only appear as options when `referenceGrams` can actually be parsed from the
/// food's serving description — without that there's nothing to scale a gram entry against, so
/// the sheet falls back to servings-only (still freely typed, just not a fixed step).
///
/// Not `private` — reused by `RecipeIngredientPickerSheet` (RecipeBuilderSheet.swift) for scaling
/// a recipe ingredient's portion, the exact same quantity/unit math as logging a meal entry.
/// Takes `confirmButtonTitle` directly rather than a `Meal` (the only thing `meal` was ever used
/// for was that button's label) so this isn't coupled to meal-logging specifically.
struct PortionConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let food: FoodSearchResult
    let confirmButtonTitle: String
    var onConfirm: (FoodSearchResult, Double, PortionUnit, Double?) -> Void

    private let referenceGrams: Double?
    @State private var unit: PortionUnit
    @State private var quantityText: String
    @FocusState private var quantityFocused: Bool
    @State private var quantityBeforeFocus: String = ""

    // Bug fix — "when I open my recipes I want to be able to edit them and see the quantities in
    // which I logged each ingredient." `RecipeBuilderSheet` reopens this sheet to re-scale an
    // already-added ingredient, and needs it seeded with that ingredient's actual saved
    // quantity/unit rather than always defaulting to the reference-gram amount — every other call
    // site (logging a food/ingredient fresh) leaves these nil and gets the old default behavior.
    init(food: FoodSearchResult, confirmButtonTitle: String, initialQuantity: Double? = nil, initialUnit: PortionUnit? = nil, onConfirm: @escaping (FoodSearchResult, Double, PortionUnit, Double?) -> Void) {
        self.food = food
        self.confirmButtonTitle = confirmButtonTitle
        self.onConfirm = onConfirm
        let grams = food.referenceGrams
        referenceGrams = grams
        _unit = State(initialValue: initialUnit ?? (grams != nil ? .g : .servings))
        _quantityText = State(initialValue: initialQuantity.map { WeightUnit.trimmedDecimal($0) } ?? (grams != nil ? WeightUnit.trimmedDecimal(grams!) : "1"))
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
                Text(confirmButtonTitle).font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white)
            }
            .buttonStyle(LiquidPrimaryButtonStyle())
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
}

/// Feature request — "I want users to be able to add their own foods on their own devices, don't
/// make it publicly shared though." Mirrors `ProgramEditorView`'s `AddCustomExerciseSheet` —
/// same "name + a few fields, save locally" shape, just with macros instead of sets/reps.
private struct AddCustomFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    var startingName: String
    var onAdd: (FoodSearchResult) -> Void

    @State private var name: String
    @State private var brand = ""
    @State private var servingDescription = "1 serving"
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbText = ""
    @State private var fatText = ""

    init(startingName: String, onAdd: @escaping (FoodSearchResult) -> Void) {
        self.startingName = startingName
        self.onAdd = onAdd
        _name = State(initialValue: startingName)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedName.isEmpty && Int(kcalText) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            Text("Add your own food").font(ForgeType.title).foregroundStyle(ForgeColors.ink)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(label: "Name", placeholder: "e.g. Mom's Chili", text: $name)
                    LabeledField(label: "Brand (optional)", placeholder: "e.g. Homemade", text: $brand)
                    LabeledField(label: "Serving description", placeholder: "e.g. 1 cup, 100g", text: $servingDescription)
                    HStack(spacing: 10) {
                        LabeledField(label: "kcal", placeholder: "0", text: $kcalText, keyboard: .numberPad)
                        LabeledField(label: "Protein (g)", placeholder: "0", text: $proteinText, keyboard: .decimalPad)
                    }
                    HStack(spacing: 10) {
                        LabeledField(label: "Carbs (g)", placeholder: "0", text: $carbText, keyboard: .decimalPad)
                        LabeledField(label: "Fat (g)", placeholder: "0", text: $fatText, keyboard: .decimalPad)
                    }
                }
            }

            Button {
                let trimmedServing = servingDescription.trimmingCharacters(in: .whitespaces)
                let food = CustomFoodStore.shared.add(
                    name: trimmedName, brand: brand, kcal: Int(kcalText) ?? 0,
                    proteinG: Double(proteinText) ?? 0, carbG: Double(carbText) ?? 0, fatG: Double(fatText) ?? 0,
                    servingDescription: trimmedServing.isEmpty ? "1 serving" : trimmedServing
                )
                onAdd(food)
                dismiss()
            } label: {
                Text("Add Food").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white)
            }
            .buttonStyle(LiquidPrimaryButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
        }
        .padding(22)
        .presentationDetents([.height(560)])
        .dismissKeyboardOnTap()
    }
}

/// Shared by `AddCustomFoodSheet` and `RecipeBuilderSheet`'s ingredient entry — a labeled
/// text field matching the `.ultraThinMaterial` field style already used throughout this file.
struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            // Feature request — "double tap the field... select all text" — plain-text fields
            // only ("not numbers"), so the numeric-keypad ones here keep the plain `TextField`.
            if keyboard == .default {
                SelectAllTextField(text: $text, placeholder: placeholder)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
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
