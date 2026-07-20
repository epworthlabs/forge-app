import SwiftUI
import Charts
import PostHog

struct ProgressTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var loggingWeight = false
    @State private var targetHitDays: Int?

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Progress").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("BODYWEIGHT").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                                Spacer()
                                Button("+ Log weight") { loggingWeight = true }
                                    .font(ForgeType.caption).foregroundStyle(ForgeColors.accent)
                            }
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
                                if let targetHitDays {
                                    Text("\(targetHitDays)/7 days").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                } else {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("RECENT PRs").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                    let records = store.personalRecords()
                    if records.isEmpty {
                        Text("Finish a workout to start tracking PRs").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    } else {
                        ForEach(records.prefix(5), id: \.exercise) { pr in
                            Text("\(pr.exercise): \(Int(pr.weightKg))kg × \(pr.reps)").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .overlay(Rectangle().fill(ForgeColors.cardBorder).frame(height: 1), alignment: .bottom)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        // Goal 05 (PRD): history-depth engagement signal for the free-first paywall decision.
        .onAppear { PostHogSDK.shared.capture("progress_viewed") }
        .sheet(isPresented: $loggingWeight) { LogWeightSheet() }
        .task { targetHitDays = await store.targetHitDaysThisWeek() }
    }
}

private struct LogWeightSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var weightLb: Double

    init() { _weightLb = State(initialValue: 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            Text("Log weight").font(ForgeType.title).foregroundStyle(ForgeColors.ink)
            HStack {
                Button { weightLb -= 0.5 } label: {
                    Image(systemName: "minus").font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38).background(ForgeColors.tileBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Spacer()
                Text(String(format: "%.1f lb", weightLb)).font(ForgeType.displayMedium).foregroundStyle(ForgeColors.ink)
                Spacer()
                Button { weightLb += 0.5 } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38).background(ForgeColors.tileBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            Button {
                store.logWeight(weightLb)
                dismiss()
            } label: {
                Text("Save").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .presentationDetents([.height(220)])
        .onAppear { weightLb = store.bodyweightLogLb.last?.weightLb ?? 150 }
    }
}
