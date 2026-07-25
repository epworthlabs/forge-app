import SwiftUI
import ForgeCore

/// Feature request — "give users a more accessible way to log their own saved recipes, they
/// shouldn't have to search for it, it should be in a separate folder/bookmark that they can
/// access." A direct list of everything in `RecipeStore`, reached via the "My Recipes" bookmark
/// button in `FoodSearchView` — distinct from search, which still finds recipes by name too (that
/// stays useful for "I remember it's called X" without knowing this list exists).
struct MyRecipesView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (Recipe) -> Void

    @ObservedObject private var recipeStore = RecipeStore.shared

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
                                onSelect(recipe)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "bookmark.fill").foregroundStyle(ForgeColors.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                        Text("\(recipe.ingredients.count) ingredients · \(recipe.asFoodSearchResult.kcal) kcal per serving")
                                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                    Spacer()
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
        }
    }
}
