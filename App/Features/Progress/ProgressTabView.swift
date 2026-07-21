import SwiftUI
import Charts
import PostHog
import ForgeCore

struct ProgressTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var loggingWeight = false
    @State private var targetHitDays: Int?
    @State private var trainingHistoryExpanded = false

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
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

                    // Feature request — "get rid of recent PR's section and replace it with lift
                    // progressions." Promoted out of the collapsed disclosure below (where it
                    // used to live alongside the calendar) into the main, always-visible flow —
                    // this is now the primary lift-tracking view, not a buried extra.
                    GlassCard {
                        LiftProgressionView(sessions: store.trailingSessions)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Feature request — calendar of training days. Collapsed by default: denser,
                    // less-glanceable data than the rest of the tab, so it stays out of the way
                    // until asked for.
                    DisclosureGroup("Workout Calendar", isExpanded: $trainingHistoryExpanded) {
                        WorkoutCalendarView(sessionDates: store.trailingSessions.map(\.date))
                            .padding(.top, 12)
                    }
                    .font(ForgeType.label)
                    .foregroundStyle(ForgeColors.inkMuted)
                    .tint(ForgeColors.ink)
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

/// Feature request — a month at a glance, marking the days a workout was completed. `sessionDates`
/// comes straight from `trailingSessions`; days are matched by calendar day, not exact timestamp.
private struct WorkoutCalendarView: View {
    let sessionDates: [Date]
    @State private var displayedMonth = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WORKOUT DAYS").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                Spacer()
                Button { shiftMonth(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.caption).foregroundStyle(ForgeColors.inkMuted)
                }
                Text(monthTitle).font(ForgeType.caption).foregroundStyle(ForgeColors.ink).frame(minWidth: 90)
                Button { shiftMonth(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(ForgeColors.inkMuted)
                }
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(daysGrid.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let trained = trainedDayNumbers.contains(calendar.component(.day, from: day))
                        Text("\(calendar.component(.day, from: day))")
                            .font(ForgeType.caption)
                            .foregroundStyle(trained ? Color.white : ForgeColors.inkMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(trained ? ForgeColors.accent : Color.clear)
                            .clipShape(Circle())
                    } else {
                        Color.clear.frame(height: 26)
                    }
                }
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] { calendar.veryShortWeekdaySymbols }

    /// Every `sessionDates` day-of-month that falls within `displayedMonth`'s year+month —
    /// intentionally not full `Date` equality, since a calendar cell only knows the day number.
    private var trainedDayNumbers: Set<Int> {
        let targetMonth = calendar.component(.month, from: displayedMonth)
        let targetYear = calendar.component(.year, from: displayedMonth)
        return Set(sessionDates.compactMap { date -> Int? in
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            guard comps.year == targetYear, comps.month == targetMonth else { return nil }
            return comps.day
        })
    }

    private var daysGrid: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday else { return [] }
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        cells += (0..<dayCount).map { calendar.date(byAdding: .day, value: $0, to: monthInterval.start) }
        return cells
    }

    private func shiftMonth(by offset: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }
}

/// Feature request — StrongLifts-style progression: pick a lift, see the heaviest working set for
/// it across every logged session. Uses the heaviest set per session (not the average) since
/// that's the number that actually defines progressive overload for that day.
private struct LiftProgressionView: View {
    let sessions: [WorkoutSession]
    @State private var selectedExercise: String?

    private var exerciseNames: [String] {
        Array(Set(sessions.flatMap { $0.sets.map(\.exerciseName) }.filter { !$0.isEmpty })).sorted()
    }

    private var dataPoints: [(date: Date, weightLb: Double)] {
        guard let selectedExercise else { return [] }
        return sessions.compactMap { session -> (Date, Double)? in
            let matches = session.sets.filter { $0.exerciseName == selectedExercise }
            guard let top = matches.max(by: { $0.weightKg < $1.weightKg }) else { return nil }
            return (session.date, WeightUnit.lb(fromKg: top.weightKg))
        }
        .sorted { $0.0 < $1.0 }
        .map { (date: $0.0, weightLb: $0.1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIFT PROGRESSION").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)

            if exerciseNames.isEmpty {
                Text("Finish a workout to see lift progression").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            } else {
                Menu {
                    ForEach(exerciseNames, id: \.self) { name in
                        Button(name) { selectedExercise = name }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedExercise ?? "Select a lift").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(ForgeColors.inkMuted)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(ForgeColors.tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .onAppear { if selectedExercise == nil { selectedExercise = exerciseNames.first } }

                if dataPoints.count < 2 {
                    Text("Log this lift a couple more times to see a trend")
                        .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        .frame(height: 120, alignment: .center)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart(dataPoints, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Weight", point.weightLb))
                            .foregroundStyle(ForgeColors.accent)
                        PointMark(x: .value("Date", point.date), y: .value("Weight", point.weightLb))
                            .foregroundStyle(ForgeColors.accent)
                    }
                    .frame(height: 140)
                    .chartXAxis(.hidden)
                }
            }
        }
    }
}
