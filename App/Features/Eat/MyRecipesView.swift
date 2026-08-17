import SwiftUI
import ForgeCore

/// Feature request — "give users a more accessible way to log their own saved recipes, they
/// shouldn't have to search for it, it should be in a separate folder/bookmark that they can
/// access." A direct list of everything in `RecipeStore`, reached via the "My Recipes" bookmark
/// button in `FoodSearchView` — distinct from search, which still finds recipes by name too (that
/// stays useful for "I remember it's called X" without knowing this list exists).
///
/// Bug fix — "when I click my recipes I want to know what food is in it." Tapping a row used to
/// jump straight to `PortionConfirmSheet` with only the recipe's summed per-serving macros —
/// `Recipe.asFoodSearchResult` collapses `ingredients` away entirely, so there was no way to see
/// what's actually in it before logging. A tap now opens `RecipeDetailSheet` (the ingredient list)
/// first; logging happens from a button there instead of from the row itself.
struct MyRecipesView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (Recipe) -> Void

    @ObservedObject private var recipeStore = RecipeStore.shared
    @State private var viewingRecipe: Recipe?

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundWash
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if recipeStore.recipes.isEmpty {
                            Text("No saved recipes yet").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                .frame(maxWidth: .infinity).padding(.top, 40)
                        }
                        ForEach(recipeStore.recipes) { recipe in
                            Button {
                                viewingRecipe = recipe
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "bookmark.fill").foregroundStyle(ForgeColors.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                        Text("\(recipe.ingredients.count) ingredients · \(recipe.asFoodSearchResult.kcal) kcal per serving")
                                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                                }
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete Recipe", role: .destructive) {
                                    recipeStore.remove(recipe)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("My Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $viewingRecipe) { recipe in
                RecipeDetailSheet(recipe: recipe) {
                    onSelect(recipe)
                    dismiss()
                } onDelete: {
                    recipeStore.remove(recipe)
                    viewingRecipe = nil
                }
            }
        }
    }
}

/// The ingredient breakdown for a single saved recipe — what tapping a row in `MyRecipesView` (or
/// a recipe result in `FoodSearchView`'s search list) now opens, before committing to logging it.
///
/// Bug fix — "when I open my recipes I want to be able to edit them and see the quantities in
/// which I logged each ingredient." `recipe` is `@State`, not `let` — seeded from the value passed
/// in but reassigned locally when `RecipeBuilderSheet`'s edit flow saves, so this sheet reflects
/// the edit immediately without needing to be closed and reopened.
private struct RecipeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var recipe: Recipe
    var onLog: () -> Void
    var onDelete: () -> Void
    @State private var editingRecipe = false

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundWash
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name).font(ForgeType.title).foregroundStyle(ForgeColors.ink)
                            Text(recipe.servings == 1 ? "1 serving" : "\(recipe.servings) servings")
                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }

                        HStack(spacing: 10) {
                            PortionMacroTile(label: "kcal", value: "\(recipe.asFoodSearchResult.kcal)")
                            PortionMacroTile(label: "Protein", value: "\(Int(recipe.asFoodSearchResult.proteinG.rounded()))g")
                            PortionMacroTile(label: "Carbs", value: "\(Int(recipe.asFoodSearchResult.carbG.rounded()))g")
                            PortionMacroTile(label: "Fat", value: "\(Int(recipe.asFoodSearchResult.fatG.rounded()))g")
                        }
                        Text("Per serving").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)

                        Text("INGREDIENTS").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted).padding(.top, 6)

                        ForEach(recipe.ingredients) { ingredient in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredient.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    // Bug fix — "see the quantities in which I logged each
                                    // ingredient, whether grams, servings, etc."
                                    Text("\(ingredient.quantityDescription) · \(Int(ingredient.proteinG))g P · \(Int(ingredient.carbG))g C · \(Int(ingredient.fatG))g F")
                                        .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                                Spacer()
                                Text("\(ingredient.kcal) kcal").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Button {
                            onLog()
                        } label: {
                            Text("Log This Recipe").font(ForgeType.title).frame(maxWidth: .infinity)
                                .padding(16).foregroundStyle(Color.white)
                        }
                        .buttonStyle(LiquidPrimaryButtonStyle())
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editingRecipe = true } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
            .sheet(isPresented: $editingRecipe) {
                RecipeBuilderSheet(existingRecipe: recipe) { updated in
                    recipe = updated
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
