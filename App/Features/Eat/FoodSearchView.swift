import SwiftUI
import ForgeCore

struct FoodSearchView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meal: Meal

    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var isSearching = false
    @State private var scannerPresented = false
    @State private var notFoundBarcode: String?
    @State private var confirmingFood: FoodSearchResult?

    var body: some View {
        NavigationStack {
            ZStack {
                ForgeColors.backgroundBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            TextField("Search or scan…", text: $query)
                                .font(ForgeType.body)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button { scannerPresented = true } label: {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.system(size: 18))
                                    .foregroundStyle(ForgeColors.ink)
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        if let notFoundBarcode {
                            Text("No match for barcode \(notFoundBarcode) — try searching by name.")
                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }

                        if query.isEmpty && !store.recentFoods.isEmpty {
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

                        Text("RESULTS").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)

                        if isSearching {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                        } else if results.isEmpty && !query.isEmpty {
                            Text("No results for \"\(query)\"").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        }

                        ForEach(results) { food in
                            Button {
                                confirmingFood = food
                            } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ForgeColors.tileBackground).frame(width: 32, height: 32)
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
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350)) // debounce — cancelled by .task(id:) on each keystroke
            guard !Task.isCancelled else { return }
            isSearching = true
            results = await store.foodSearchService.search(query: query)
            isSearching = false
        }
        .sheet(isPresented: $scannerPresented) {
            BarcodeScannerView { code in
                Task {
                    if let match = await store.lookupBarcode(code) {
                        confirmingFood = match
                    } else {
                        notFoundBarcode = code
                    }
                }
            }
        }
        .sheet(item: $confirmingFood) { food in
            PortionConfirmSheet(food: food, meal: meal) { scaledFood in
                store.logFood(scaledFood, to: meal)
                dismiss()
            }
        }
    }
}

private struct PortionConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let food: FoodSearchResult
    let meal: Meal
    var onConfirm: (FoodSearchResult) -> Void

    @State private var multiplier: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(ForgeType.title).foregroundStyle(ForgeColors.ink)
                if let brand = food.brand {
                    Text(brand).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Portion").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                    Text(food.servingDescription).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                }
                Spacer()
                Button { multiplier = max(0.25, multiplier - 0.25) } label: {
                    Image(systemName: "minus").font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34).foregroundStyle(ForgeColors.ink)
                        .background(ForgeColors.tileBackground).clipShape(Circle())
                }
                Text("\(trimmedDecimal(multiplier))×").font(ForgeType.title).foregroundStyle(ForgeColors.ink).frame(width: 54)
                Button { multiplier += 0.25 } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34).foregroundStyle(ForgeColors.ink)
                        .background(ForgeColors.tileBackground).clipShape(Circle())
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                PortionMacroTile(label: "kcal", value: "\(scaledKcal)")
                PortionMacroTile(label: "Protein", value: "\(Int(scaledProtein))g")
                PortionMacroTile(label: "Carbs", value: "\(Int(scaledCarb))g")
                PortionMacroTile(label: "Fat", value: "\(Int(scaledFat))g")
            }

            Button {
                onConfirm(scaled(food, by: multiplier))
            } label: {
                Text("Add to \(meal.rawValue)").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .presentationDetents([.height(360)])
    }

    private var scaledKcal: Int { Int((Double(food.kcal) * multiplier).rounded()) }
    private var scaledProtein: Double { food.proteinG * multiplier }
    private var scaledCarb: Double { food.carbG * multiplier }
    private var scaledFat: Double { food.fatG * multiplier }

    private func scaled(_ food: FoodSearchResult, by multiplier: Double) -> FoodSearchResult {
        FoodSearchResult(
            id: food.id, name: food.name, brand: food.brand,
            kcal: scaledKcal, proteinG: scaledProtein, carbG: scaledCarb, fatG: scaledFat,
            servingDescription: multiplier == 1.0 ? food.servingDescription : "\(trimmedDecimal(multiplier))× \(food.servingDescription)",
            source: food.source, barcodeUPC: food.barcodeUPC
        )
    }

    private func trimmedDecimal(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

private struct PortionMacroTile: View {
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
