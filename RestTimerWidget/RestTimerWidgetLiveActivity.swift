import ActivityKit
import SwiftUI
import WidgetKit

// Feature request — "rest timer as an app notification... shows the timer on the lock screen."
// The Lock Screen/banner presentation and the Dynamic Island are both declared here, in the widget
// extension — that split is an ActivityKit requirement, not a choice: the app process starts and
// updates the Activity (`RestTimerActivityManager`), but only a widget extension target can supply
// the SwiftUI that renders it, since that UI runs even while the app itself is suspended.
struct RestTimerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenView(state: context.state, exerciseName: context.attributes.exerciseName)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(endDate: context.state.endDate)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.exerciseName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                CountdownText(endDate: context.state.endDate)
                    .font(.caption.monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

private struct LockScreenView: View {
    let state: RestTimerAttributes.ContentState
    let exerciseName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                CountdownText(endDate: state.endDate)
                    .font(.title.monospacedDigit())
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(16)
    }
}

// `Text(timerInterval:)` requires a valid (non-inverted) range — once `endDate` has passed (the
// app doesn't tear the Activity down the instant rest hits zero, only when the next set starts or
// the workout finishes), `Date()...endDate` would crash. Falls back to a static "Rest complete"
// label for that window instead.
private struct CountdownText: View {
    let endDate: Date

    var body: some View {
        if endDate > Date() {
            Text(timerInterval: Date()...endDate, countsDown: true)
        } else {
            Text("Rest complete")
        }
    }
}

@main
struct RestTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestTimerWidgetLiveActivity()
    }
}
