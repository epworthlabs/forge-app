import SwiftUI
import ForgeCore

/// Feature request — "review the workout they just did/logged that day." Originally read
/// `store.lastCompletedSession` directly since there was only ever one reviewable session at a
/// time; now takes an explicit session so it can review *any* historical session — today's from
/// Today, or a specific past day's from Progress's calendar.
struct SessionReviewView: View {
    let session: WorkoutSession

    private var byExercise: [(name: String, sets: [SetLog])] {
        var order: [String] = []
        var grouped: [String: [SetLog]] = [:]
        for set in session.sets {
            if grouped[set.exerciseName] == nil { order.append(set.exerciseName) }
            grouped[set.exerciseName, default: []].append(set)
        }
        return order.map { (name: $0, sets: grouped[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(session.date, style: .date).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)

                    if byExercise.isEmpty {
                        Text("Nothing to review yet.").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    } else {
                        ForEach(byExercise, id: \.name) { entry in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.name).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    ForEach(Array(entry.sets.enumerated()), id: \.offset) { _, set in
                                        HStack {
                                            Text("\(WeightUnit.roundedLb(fromKg: set.weightKg)) lb × \(set.reps)")
                                                .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                            if let rpe = set.rpe {
                                                Spacer()
                                                Text("RPE \(String(format: "%.0f", rpe))").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Workout Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
