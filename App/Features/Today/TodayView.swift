import SwiftUI
import ForgeCore

struct TodayView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedTab: MainTab
    @State private var reviewingSession = false

    private var todaysCompletedSession: WorkoutSession? {
        guard let session = store.lastCompletedSession, Calendar.current.isDateInToday(session.date) else { return nil }
        return session
    }

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

                    // Feature request — "get rid of adjustments that happen to calorie amounts
                    // after training... calorie amounts were not supposed to change." Target is
                    // now fixed by activity level + goal + weekly recalibration only, so there's
                    // no more per-day "adjusted for training" state to show here.
                    Button { store.sheetPresented = true } label: {
                        GlassCard(cornerRadius: 28) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("NUTRITION TARGET").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                    .padding(.bottom, 10)

                                HStack(spacing: 12) {
                                    LiquidTile(label: "Calories", value: "\(Int(target.calories))")
                                    LiquidTile(label: "Protein", value: "\(Int(target.proteinG))g")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    // Feature request — "get rid of the ring called sets logged, instead, when
                    // user completes their workout, give them a checkbox that denotes that todays
                    // workout is complete and if they tap, allow them to review the workout."
                    if let session = todaysCompletedSession {
                        Button { reviewingSession = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22)).foregroundStyle(ForgeColors.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Today's workout complete").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    Text("Tap to review").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                            }
                            .padding(16)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $reviewingSession) {
                            NavigationStack { SessionReviewView(session: session) }
                        }
                    }

                    if store.hasTrainingHistory {
                        RingStat(label: "kcal eaten", value: "\(totals.kcal)",
                                 progress: target.calories > 0 ? min(1.0, Double(totals.kcal) / target.calories) : 0, color: ForgeColors.accent2)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Macros").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            LiquidMacroRow(label: "Protein", current: totals.protein, target: Int(target.proteinG), color: ForgeColors.accent)
                            LiquidMacroRow(label: "Carbs", current: totals.carb, target: Int(target.carbG), color: ForgeColors.accent2)
                            LiquidMacroRow(label: "Fat", current: totals.fat, target: Int(target.fatG), color: ForgeColors.accent3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GlassCard {
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
                        DashedActionButton(title: "+ Log food") { selectedTab = .eat }
                        DashedActionButton(title: "+ Log weight") { selectedTab = .progress }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $store.sheetPresented) { TargetExplanationSheet() }
    }
}
