import SwiftUI
import ForgeCore

/// Feature request — "I want users to be able to group a collection of foods and save + input it
/// as a recipe." Search-and-pick ingredients one at a time (reusing the exact same portion-scaling
/// flow as logging a single food — see `PortionConfirmSheet`), then save the whole thing as a
/// `Recipe` via `RecipeStore`. `FoodSearchView` already merges saved recipes back into its own
/// search results (as a single `FoodSearchResult` per recipe — see `Recipe.asFoodSearchResult`),
/// so logging one afterward needs no dedicated code path at all.
struct RecipeBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Recipe) -> Void

    @State private var recipeName = ""
    @State private var servingsText = "1"
    @State private var ingredients: [RecipeIngredient] = []
    @State private var addingIngredient = false

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

                        ForEach(ingredients) { ingredient in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredient.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    Text("\(ingredient.kcal) kcal · \(Int(ingredient.proteinG))g P · \(Int(ingredient.carbG))g C · \(Int(ingredient.fatG))g F")
                                        .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                                Spacer()
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
                            let recipe = Recipe(name: trimmedName, servings: servings, ingredients: ingredients)
                            RecipeStore.shared.add(recipe)
                            onSave(recipe)
                            dismiss()
                        } label: {
                            Text("Save Recipe").font(ForgeType.title).frame(maxWidth: .infinity)
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
            .navigationTitle("New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $addingIngredient) {
                RecipeIngredientPickerSheet { ingredient in
                    ingredients.append(ingredient)
                }
            }
        }
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
            PortionConfirmSheet(food: food, confirmButtonTitle: "Add Ingredient") { originalFood, quantity, unit, referenceGrams in
                let multiplier = PortionScaling.multiplier(quantity: quantity, unit: unit, referenceGrams: referenceGrams)
                let ingredient = RecipeIngredient(
                    name: originalFood.name,
                    kcal: Int((Double(originalFood.kcal) * multiplier).rounded()),
                    proteinG: originalFood.proteinG * multiplier,
                    carbG: originalFood.carbG * multiplier,
                    fatG: originalFood.fatG * multiplier
                )
                onAdd(ingredient)
                dismiss()
            }
        }
    }
}
