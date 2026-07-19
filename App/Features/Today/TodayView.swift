import SwiftUI
import ForgeCore

struct GlassCard<Content: View>: View {
    var dashed: Bool = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : []))
            )
    }
}

struct TodayView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedTab: MainTab

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Date(), style: .date).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            Text("Today").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                        }
                        Spacer()
                        Circle().fill(.ultraThinMaterial).frame(width: 38, height: 38)
                    }

                    let target = store.nutritionTarget

                    Button { store.sheetPresented = true } label: {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NUTRITION TARGET").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                Text("\(Int(target.calories)) kcal").font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
                                if target.calorieAdjustment != 0 {
                                    let sign = target.calorieAdjustment > 0 ? "+" : ""
                                    Text("\(sign)\(Int(target.calorieAdjustment)) kcal · Load \(String(format: "%.1f", target.loadScore))×")
                                        .font(ForgeType.caption).foregroundStyle(Color.white)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(ForgeColors.accent).clipShape(Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    if store.hasTrainingHistory {
                        HStack(spacing: 14) {
                            LoadRing(label: "Training load", value: String(format: "%.1f×", target.loadScore))
                            LoadRing(label: "kcal eaten", value: "\(store.totals().kcal)")
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Macros").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            let totals = store.totals()
                            MacroRow(label: "Protein", current: totals.protein, target: Int(target.proteinG), color: ForgeColors.ink)
                            MacroRow(label: "Carbs", current: totals.carb, target: Int(target.carbG), color: ForgeColors.accent2)
                            MacroRow(label: "Fat", current: totals.fat, target: Int(target.fatG), color: ForgeColors.accent3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GlassCard(dashed: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TODAY'S WORKOUT").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                            Text(store.program.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            Text(store.todaysExercises.map(\.exercise.name).joined(separator: " · "))
                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted).lineLimit(1)
                            Button { selectedTab = .train } label: {
                                Text("Start Workout").font(ForgeType.title).frame(maxWidth: .infinity)
                                    .padding(13).foregroundStyle(Color.white).background(ForgeColors.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        QuickAction(title: "+ Log food") { selectedTab = .eat }
                        QuickAction(title: "+ Log weight") { selectedTab = .progress }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $store.sheetPresented) { TargetExplanationSheet() }
    }
}

private struct LoadRing: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(ForgeColors.trackBackground, lineWidth: 4)
                Text(value).font(ForgeType.title).foregroundStyle(ForgeColors.ink)
            }
            .frame(width: 74, height: 74)
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MacroRow: View {
    let label: String
    let current: Int
    let target: Int
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted).frame(width: 56, alignment: .leading)
            GeometryReader { geo in
                let pct = target > 0 ? min(1.0, Double(current) / Double(target)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgeColors.trackBackground)
                    Capsule().fill(color).frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 8)
            Text("\(current)/\(target)g").font(ForgeType.caption).foregroundStyle(ForgeColors.ink).frame(width: 76, alignment: .trailing)
        }
    }
}

private struct QuickAction: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(ForgeType.body).frame(maxWidth: .infinity)
                .padding(14).foregroundStyle(ForgeColors.ink)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
}
