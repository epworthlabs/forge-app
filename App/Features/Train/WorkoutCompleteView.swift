import SwiftUI
import UIKit
import ForgeCore

/// Feature request — "when user hits complete workout, display a congratulatory screen." Shown as
/// a full-screen cover (not pushed) so it reads as a distinct moment, not just another screen in
/// the flow. Stats come from `store.lastCompletedSession`, set by `AppStore.finishWorkout()`.
struct WorkoutCompleteView: View {
    @EnvironmentObject var store: AppStore
    var onContinue: () -> Void

    private var session: WorkoutSession? { store.lastCompletedSession }
    private var exerciseCount: Int { Set((session?.sets ?? []).map(\.exerciseName)).count }
    private var setCount: Int { session?.sets.count ?? 0 }
    private var totalVolumeLb: Int {
        Int((session?.sets ?? []).reduce(0.0) { $0 + WeightUnit.lb(fromKg: $1.weightKg) * Double($1.reps) }.rounded())
    }
    // Feature request — "the whole workout should be timed so upon completion, users know how
    // long their workout session was." nil (shown as "—") only for a session logged before this
    // field existed, or the rare case where a start was never recorded.
    private var durationText: String {
        guard let seconds = session?.durationSeconds else { return "—" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(ForgeColors.accent)
                VStack(spacing: 8) {
                    Text("Workout Complete!").font(ForgeType.displayLarge).tracking(-0.6).liquidHeadingStyle()
                    Text("Nice work — that's one more session in the bank.")
                        .font(ForgeType.body).foregroundStyle(ForgeColors.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // 2x2 grid, not a single 4-wide row — "Volume" and "Duration" can both run to
                // 5-6 characters, and a quarter-width tile at this font size would feel squished.
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        StatTile(label: "Exercises", value: "\(exerciseCount)")
                        StatTile(label: "Sets", value: "\(setCount)")
                    }
                    HStack(spacing: 12) {
                        StatTile(label: "Volume", value: "\(totalVolumeLb) lb")
                        StatTile(label: "Duration", value: durationText)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button(action: onContinue) {
                    Text("Continue").font(ForgeType.title).frame(maxWidth: .infinity)
                        .padding(16).foregroundStyle(Color.white)
                }
                .buttonStyle(LiquidPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(ForgeType.title).foregroundStyle(ForgeColors.ink)
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
