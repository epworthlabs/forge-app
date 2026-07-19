import SwiftUI

/// Placeholder food data — stand-in for the USDA FDC / Open Food Facts / FatSecret pipeline
/// (FRG-120–123, not yet built). Manual search only for v1; barcode scanning is FRG-125 (P1).
private let mockFoodDatabase: [FoodEntry] = [
    FoodEntry(name: "Chicken Breast, grilled", kcal: 231, proteinG: 43, carbG: 0, fatG: 5),
    FoodEntry(name: "Brown Rice, 1 cup", kcal: 216, proteinG: 5, carbG: 45, fatG: 2),
    FoodEntry(name: "Broccoli, steamed", kcal: 55, proteinG: 4, carbG: 11, fatG: 1),
    FoodEntry(name: "Greek Yogurt, plain", kcal: 100, proteinG: 17, carbG: 6, fatG: 0),
    FoodEntry(name: "Almonds, 1 oz", kcal: 164, proteinG: 6, carbG: 6, fatG: 14),
]

struct FoodSearchView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    @State private var query = ""

    private var results: [FoodEntry] {
        guard !query.isEmpty else { return mockFoodDatabase }
        return mockFoodDatabase.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Search food…", text: $query)
                            .font(ForgeType.body)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Text("RESULTS").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)

                        ForEach(results) { food in
                            Button {
                                store.addFood(food, to: meal)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ForgeColors.tileBackground).frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(food.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                        Text("\(food.proteinG)g P · \(food.carbG)g C · \(food.fatG)g F")
                                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                    Spacer()
                                    Text("\(food.kcal)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Text("USDA FDC · Open Food Facts · FatSecret")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            .frame(maxWidth: .infinity).padding(.top, 12)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add to \(meal.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
