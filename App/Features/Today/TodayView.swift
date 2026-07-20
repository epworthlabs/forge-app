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

/// Today-only for now — the "Liquid Glass" reskin (frosted blur, oklch-derived palette, inset
/// highlight) matches ../../../Wireframes/updated/uploads/.../TodayGlassLight+Dark.dc.html
/// exactly. Deliberately a separate type from `GlassCard` above (used by every other screen) so
/// this pass doesn't change anything outside Today — the plan is to roll the same system out
/// elsewhere once this is confirmed live, not change every screen's look in one shot.
private struct LiquidCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(20)
            .background(ForgeColors.cardBackground)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ForgeColors.cardBorder, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ForgeColors.cardHighlight, lineWidth: 1)
                    .blendMode(.plusLighter)
                    .padding(0.5)
            )
            .shadow(color: ForgeColors.cardShadow, radius: 16, x: 0, y: 8)
    }
}

struct TodayView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedTab: MainTab

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Date(), style: .date).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            Text("Today").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                        }
                        Spacer()
                        Circle()
                            .fill(ForgeColors.avatarBackground)
                            .overlay(Circle().strokeBorder(ForgeColors.avatarBorder, lineWidth: 1))
                            .background(.ultraThinMaterial, in: Circle())
                            .frame(width: 38, height: 38)
                    }

                    let target = store.nutritionTarget
                    let totals = store.totals()

                    Button { store.sheetPresented = true } label: {
                        LiquidCard(cornerRadius: 28) {
                            VStack(alignment: .leading, spacing: 0) {
                                if target.calorieAdjustment != 0 {
                                    HStack(spacing: 8) {
                                        Circle().fill(ForgeColors.accent).frame(width: 7, height: 7)
                                        Text("Adjusted for today's training")
                                            .font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                                    }
                                    .padding(.bottom, 10)
                                } else {
                                    Text("NUTRITION TARGET").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                        .padding(.bottom, 10)
                                }

                                HStack(spacing: 12) {
                                    LiquidTile(label: "Calories", value: "\(Int(target.calories))",
                                               delta: target.calorieAdjustment != 0 ? signedInt(target.calorieAdjustment) + " today" : nil)
                                    LiquidTile(label: "Protein", value: "\(Int(target.proteinG))g", delta: nil)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    if store.hasTrainingHistory {
                        HStack(spacing: 14) {
                            let doneSets = store.todaysExercises.flatMap(\.sets).filter(\.done).count
                            let totalSets = store.todaysExercises.flatMap(\.sets).count
                            RingStat(label: "Sets logged", value: "\(doneSets)/\(totalSets)",
                                     progress: totalSets > 0 ? Double(doneSets) / Double(totalSets) : 0, color: ForgeColors.accent)
                            RingStat(label: "kcal eaten", value: "\(totals.kcal)",
                                     progress: target.calories > 0 ? min(1.0, Double(totals.kcal) / target.calories) : 0, color: ForgeColors.accent2)
                        }
                    }

                    LiquidCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Macros").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            LiquidMacroRow(label: "Protein", current: totals.protein, target: Int(target.proteinG), color: ForgeColors.accent)
                            LiquidMacroRow(label: "Carbs", current: totals.carb, target: Int(target.carbG), color: ForgeColors.accent2)
                            LiquidMacroRow(label: "Fat", current: totals.fat, target: Int(target.fatG), color: ForgeColors.accent3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    LiquidCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.currentProgramDayName).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
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

    private func signedInt(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value))"
    }
}

private struct LiquidTile: View {
    let label: String
    let value: String
    let delta: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(ForgeColors.ink)
            if let delta {
                Text(delta).font(ForgeType.caption).fontWeight(.semibold).foregroundStyle(ForgeColors.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ForgeColors.tileBorder, lineWidth: 1))
    }
}

private struct RingStat: View {
    let label: String
    let value: String
    let progress: Double
    let color: Color
    var body: some View {
        LiquidCard {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(ForgeColors.ringTrack, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: max(0.001, min(1, progress)))
                        .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().fill(ForgeColors.ringFillBackground).padding(9)
                    Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(ForgeColors.ink)
                }
                .frame(width: 74, height: 74)
                Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LiquidMacroRow: View {
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
