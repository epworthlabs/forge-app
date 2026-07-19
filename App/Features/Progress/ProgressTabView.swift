import SwiftUI
import Charts

struct ProgressTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Progress").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BODYWEIGHT").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                            // A single weigh-in (the day-one default from onboarding) has nothing to
                            // draw a trend line between — a LineMark silently renders as nothing, which
                            // reads as a broken chart rather than an honest "not enough data yet" state.
                            if store.bodyweightLogLb.count < 2 {
                                Text("Log a couple more weigh-ins to see your trend")
                                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    .frame(height: 90, alignment: .center)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Chart(store.bodyweightLogLb, id: \.date) { point in
                                    LineMark(x: .value("Date", point.date), y: .value("Weight", point.weightLb))
                                        .foregroundStyle(ForgeColors.inkMuted)
                                }
                                .frame(height: 90)
                                .chartXAxis(.hidden)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GlassCard(dashed: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("THIS WEEK").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                            HStack {
                                Text("Workouts completed").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                Spacer()
                                Text("\(store.workoutsCompletedThisWeek)/\(store.workoutsPlannedThisWeek)").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            }
                            HStack {
                                Text("Target hit").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                Spacer()
                                Text("5/7 days").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("RECENT PRs").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                    ForEach(["Back Squat: 225×5", "Bench Press: 165×5"], id: \.self) { pr in
                        Text(pr).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .overlay(Rectangle().fill(ForgeColors.cardBorder).frame(height: 1), alignment: .bottom)
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
    }
}
