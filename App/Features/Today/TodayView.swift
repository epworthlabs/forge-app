import SwiftUI
import ForgeCore

struct TodayView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedTab: MainTab
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @State private var reviewingSession = false

    // Bug fix — "if I start a new workout it'll revert back to not done yet, if a user marks off
    // a workout for that day, it should not revert back to incomplete." This used to read
    // `store.lastCompletedSession`, a transient "just finished, offer a review" pointer that
    // `selectDay` clears to nil the moment the user taps *any* day tile (even just to start a
    // different workout) — so completing today's workout, then merely opening Train again, made
    // this tile forget it ever happened. Deriving from `trailingSessions` (persistent history)
    // instead means it reflects reality regardless of what else the user has navigated to since.
    private var todaysCompletedSession: WorkoutSession? {
        store.trailingSessions.last { Calendar.current.isDateInToday($0.date) }
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
                        // Feature request — "make sure it reflects the image in the profile
                        // section of the you page." Was a plain placeholder circle, never wired
                        // to `ProfileSettings` at all.
                        AvatarView(imageData: profileSettings.avatarImageData, size: 38)
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

                    // Feature request — "I want that square tile with the ring that shows % of
                    // calories consumed fixed on the home screen below the nutrition target card.
                    // Beside it, place and fix the checkbox tile denoting a workout complete."
                    // Both tiles are now always present (previously each collapsed away under its
                    // own gating condition — training history for the ring, an unfinished workout
                    // for the checkbox — which is exactly what made them feel like they moved
                    // around rather than living in a fixed spot).
                    HStack(spacing: 12) {
                        RingStat(label: "kcal eaten", value: "\(totals.kcal)",
                                 progress: target.calories > 0 ? min(1.0, Double(totals.kcal) / target.calories) : 0, color: ForgeColors.accent2)
                        WorkoutStatusTile(session: todaysCompletedSession) { reviewingSession = true }
                    }
                    .sheet(isPresented: $reviewingSession) {
                        if let session = todaysCompletedSession {
                            NavigationStack { SessionReviewView(session: session) }
                        }
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

/// The square, ring-shaped counterpart to `RingStat` for workout-complete status — same footprint
/// (`GlassCard`, 74×74 ring) so the two sit evenly side by side. Tapping only does something once
/// there's a session to review; an unfinished day renders as a plain empty ring, not a dead button.
private struct WorkoutStatusTile: View {
    let session: WorkoutSession?
    var onTap: () -> Void

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(ForgeColors.ringTrack, lineWidth: 8)
                    if session != nil {
                        Circle().stroke(ForgeColors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    }
                    Circle().fill(ForgeColors.ringFillBackground).padding(9)
                    Image(systemName: session != nil ? "checkmark" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(session != nil ? ForgeColors.accent : ForgeColors.inkMuted)
                }
                .frame(width: 74, height: 74)
                Text(session != nil ? "Workout done" : "Not done yet").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { if session != nil { onTap() } }
    }
}
