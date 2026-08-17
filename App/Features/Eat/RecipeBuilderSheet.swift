import SwiftUI
import ForgeCore

/// Feature request — "I want users to be able to group a collection of foods and save + input it
/// as a recipe." Search-and-pick ingredients one at a time (reusing the exact same portion-scaling
/// flow as logging a single food — see `PortionConfirmSheet`), then save the whole thing as a
/// `Recipe` via `RecipeStore`. `FoodSearchView` already merges saved recipes back into its own
/// search results (as a single `FoodSearchResult` per recipe — see `Recipe.asFoodSearchResult`),
/// so logging one afterward needs no dedicated code path at all.
///
/// Bug fix — "when I open my recipes I want to be able to edit them." `existingRecipe` switches
/// this between "build a new one" and "edit an already-saved one" — same fields, just seeded from
/// the recipe and saved via `RecipeStore.update` instead of `.add`.
struct RecipeBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    var existingRecipe: Recipe?
    var onSave: (Recipe) -> Void

    @State private var recipeName: String
    @State private var servingsText: String
    @State private var ingredients: [RecipeIngredient]
    @State private var addingIngredient = false
    // Bug fix — "see the quantities in which I logged each ingredient, whether grams, servings,
    // etc." Tapping an already-added ingredient (rather than only the trash icon) reopens
    // `PortionConfirmSheet` seeded with its actual saved quantity/unit, so it can be rescaled in
    // place instead of only removed and re-added from scratch.
    @State private var editingIngredient: RecipeIngredient?

    init(existingRecipe: Recipe? = nil, onSave: @escaping (Recipe) -> Void) {
        self.existingRecipe = existingRecipe
        self.onSave = onSave
        _recipeName = State(initialValue: existingRecipe?.name ?? "")
        _servingsText = State(initialValue: String(existingRecipe?.servings ?? 1))
        _ingredients = State(initialValue: existingRecipe?.ingredients ?? [])
    }

    private var trimmedName: String { recipeName.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedName.isEmpty && !ingredients.isEmpty }
    private var totalKcal: Int { ingredients.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundWash
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledField(label: "Recipe name", placeholder: "e.g. Sunday Meal Prep Bowl", text: $recipeName)

                        HStack {
                            Text("Yields").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            Spacer()
                            TextField("1", text: $servingsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                                .padding(8)
                                .background(ForgeColors.tileBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("servings").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }

                        Text("INGREDIENTS").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)

                        if ingredients.isEmpty {
                            Text("Add a few foods to build this recipe").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }

                        // Bug fix — "see the quantities in which I logged each ingredient." Tap
                        // the row to rescale it, trash icon stays a separate sibling button (not
                        // nested inside the row's Button — nesting one Button in another's label
                        // is fragile in SwiftUI, same reasoning as the star button in
                        // `FoodSearchView`'s result rows).
                        ForEach(ingredients) { ingredient in
                            HStack {
                                Button {
                                    editingIngredient = ingredient
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ingredient.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                        Text("\(ingredient.quantityDescription) · \(ingredient.kcal) kcal · \(Int(ingredient.proteinG))g P · \(Int(ingredient.carbG))g C · \(Int(ingredient.fatG))g F")
                                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Button { ingredients.removeAll { $0.id == ingredient.id } } label: {
                                    Image(systemName: "trash").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        DashedActionButton(title: "+ Add Ingredient") { addingIngredient = true }

                        if !ingredients.isEmpty {
                            Text("Total: \(totalKcal) kcal across \(ingredients.count) ingredient\(ingredients.count == 1 ? "" : "s")")
                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }

                        Button {
                            let servings = max(1, Int(servingsText) ?? 1)
                            let recipe = Recipe(id: existingRecipe?.id ?? UUID(), name: trimmedName, servings: servings, ingredients: ingredients)
                            if existingRecipe != nil {
                                RecipeStore.shared.update(recipe)
                            } else {
                                RecipeStore.shared.add(recipe)
                            }
                            onSave(recipe)
                            dismiss()
                        } label: {
                            Text(existingRecipe == nil ? "Save Recipe" : "Save Changes").font(ForgeType.title).frame(maxWidth: .infinity)
                                .padding(16).foregroundStyle(Color.white)
                        }
                        .buttonStyle(LiquidPrimaryButtonStyle())
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                    }
                    .padding(20)
                }
                .dismissKeyboardOnTap()
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle(existingRecipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $addingIngredient) {
                RecipeIngredientPickerSheet { ingredient in
                    ingredients.append(ingredient)
                }
            }
            .sheet(item: $editingIngredient) { ingredient in
                PortionConfirmSheet(
                    food: asFoodSearchResult(ingredient), confirmButtonTitle: "Update Ingredient",
                    initialQuantity: ingredient.quantity, initialUnit: ingredient.unit
                ) { originalFood, quantity, unit, referenceGrams in
                    let multiplier = PortionScaling.multiplier(quantity: quantity, unit: unit, referenceGrams: referenceGrams)
                    let updated = RecipeIngredient(
                        id: ingredient.id, name: originalFood.name,
                        kcal: Int((Double(originalFood.kcal) * multiplier).rounded()),
                        proteinG: originalFood.proteinG * multiplier,
                        carbG: originalFood.carbG * multiplier,
                        fatG: originalFood.fatG * multiplier,
                        quantity: quantity, unit: unit, referenceGrams: referenceGrams,
                        baseKcal: Double(originalFood.kcal), baseProteinG: originalFood.proteinG,
                        baseCarbG: originalFood.carbG, baseFatG: originalFood.fatG
                    )
                    if let idx = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
                        ingredients[idx] = updated
                    }
                }
            }
        }
    }

    // Reconstructs the per-1-unit "food" `PortionConfirmSheet` needs from an already-added
    // ingredient's stored base macros, so re-opening it to rescale reads the same way logging it
    // fresh did — `servingDescription` encodes `referenceGrams` back into text since that's how
    // `FoodSearchResult.referenceGrams` recovers it (see that computed property's doc comment).
    private func asFoodSearchResult(_ ingredient: RecipeIngredient) -> FoodSearchResult {
        FoodSearchResult(
            id: "ingredient-\(ingredient.id.uuidString)", name: ingredient.name,
            kcal: Int(ingredient.effectiveBaseKcal.rounded()), proteinG: ingredient.effectiveBaseProteinG,
            carbG: ingredient.effectiveBaseCarbG, fatG: ingredient.effectiveBaseFatG,
            servingDescription: ingredient.referenceGrams.map { "per \(WeightUnit.trimmedDecimal($0))g" } ?? "1 serving",
            source: .custom
        )
    }
}

/// A trimmed-down `FoodSearchView` — search, pick, scale a portion — that hands back a
/// `RecipeIngredient` (the scaled macro snapshot) instead of logging a `FoodEntry`.
private struct RecipeIngredientPickerSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var onAdd: (RecipeIngredient) -> Void

    @ObservedObject private var customFoods = CustomFoodStore.shared
    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var isSearching = false
    @State private var confirmingFood: FoodSearchResult?

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundWash
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        SelectAllTextField(text: $query, placeholder: "Search ingredients…")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if isSearching {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                        } else if results.isEmpty && !query.isEmpty {
                            Text("No results for \"\(query)\"").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }

                        ForEach(results.prefix(40)) { food in
                            Button { confirmingFood = food } label: {
                                HStack(spacing: 10) {
                                    FoodMonogram(name: food.name).frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(food.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                        Text("\(Int(food.proteinG))g P · \(Int(food.carbG))g C · \(Int(food.fatG))g F · \(food.servingDescription)")
                                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                    Spacer()
                                    Text("\(food.kcal)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(20)
                }
                .dismissKeyboardOnTap()
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            let local = customFoods.search(query)
            let networked = await store.foodSearchService.search(query: query)
            results = local + networked
            isSearching = false
        }
        .sheet(item: $confirmingFood) { food in
            // Bug fix — "see the quantities in which I logged each ingredient." Now records the
            // quantity/unit/referenceGrams and base (per-1-unit) macros alongside the scaled
            // snapshot, so this ingredient's portion can be redisplayed and re-edited later — see
            // `RecipeIngredient`'s doc comment.
            PortionConfirmSheet(food: food, confirmButtonTitle: "Add Ingredient") { originalFood, quantity, unit, referenceGrams in
                let multiplier = PortionScaling.multiplier(quantity: quantity, unit: unit, referenceGrams: referenceGrams)
                let ingredient = RecipeIngredient(
                    name: originalFood.name,
                    kcal: Int((Double(originalFood.kcal) * multiplier).rounded()),
                    proteinG: originalFood.proteinG * multiplier,
                    carbG: originalFood.carbG * multiplier,
                    fatG: originalFood.fatG * multiplier,
                    quantity: quantity, unit: unit, referenceGrams: referenceGrams,
                    baseKcal: Double(originalFood.kcal), baseProteinG: originalFood.proteinG,
                    baseCarbG: originalFood.carbG, baseFatG: originalFood.fatG
                )
                onAdd(ingredient)
                dismiss()
            }
        }
    }
}
