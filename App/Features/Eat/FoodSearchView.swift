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
                                            store.logFood(food, to: meal)
                                            dismiss()
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
                                store.logFood(food, to: meal)
                                dismiss()
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
                        store.logFood(match, to: meal)
                        dismiss()
                    } else {
                        notFoundBarcode = code
                    }
                }
            }
        }
    }
}
