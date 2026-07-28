import SwiftUI
import ForgeCore

/// Feature request — shown after picking a program, and again after Finish Workout (item 3: "bring
/// them to another screen where users can either review the workout they just did or select a
/// different workout from that week"). The day Finish Workout just rotated to is highlighted as
/// the suggested next session; a review tile appears only while there's something to review.
struct DaySelectionView: View {
    @EnvironmentObject var store: AppStore
    var onSelectDay: (Int, Int) -> Void
    var onReview: () -> Void

    // Feature request — "allow users to traverse through multiple weeks, ex. week 1 of 12, week 4
    // of 12." nil means "just show wherever the suggested session actually is" — avoids needing
    // `store` (an @EnvironmentObject, not available yet inside init) to seed this at construction
    // time; only set once the user actually pages away from that.
    //
    // Bug fix — "when the user taps into a workout program, it should display the week that the
    // suggested workout is at, not week 1." This used to default to `store.currentProgramWeek` —
    // the real calendar week — which reads as "week 1" whenever someone's training faster than
    // the program's own cadence (e.g. done every day, so this calendar week's content is already
    // finished by day 3 or 4): the suggestion has already moved on to a later week, but this
    // screen still opened on the calendar's week. `suggestedSession()` is where the suggestion
    // actually lives, which is what should open by default.
    @State private var manuallySelectedWeek: Int?
    private var viewingWeek: Int { manuallySelectedWeek ?? store.suggestedSession().week }

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.program.name).font(ForgeType.displayLarge).tracking(-0.6).liquidHeadingStyle()
                        HStack(spacing: 10) {
                            IconButton(systemName: "chevron.left", action: { shiftWeek(by: -1) }, size: 32)
                                .disabled(viewingWeek <= 1)
                                .opacity(viewingWeek <= 1 ? 0.4 : 1)
                            Text("Week \(viewingWeek) of \(store.program.weekCount)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            IconButton(systemName: "chevron.right", action: { shiftWeek(by: 1) }, size: 32)
                                .disabled(viewingWeek >= store.program.weekCount)
                                .opacity(viewingWeek >= store.program.weekCount ? 0.4 : 1)
                        }
                    }

                    if store.lastCompletedSession != nil {
                        Button(action: onReview) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nice work!").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    Text("Review the workout you just finished").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                            }
                            .padding(16)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(viewingWeek == store.currentProgramWeek ? "This week" : "Week \(viewingWeek)")
                        .font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                    let days = store.program.days(forWeek: viewingWeek)
                    if days.isEmpty {
                        Text("This program doesn't have any days set up yet.").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    } else {
                        // Feature request — "denote that specific workout was completed for the
                        // week... suggest the next workout depending on the week and what has
                        // already been done." Bug fix — "it should never suggest a completed
                        // workout" — `suggestedSession()` (not a per-week lookup) is what actually
                        // finds the next uncompleted day, which may be a different week than the
                        // one being browsed here.
                        let completed = store.completedDayIndices(forWeek: viewingWeek)
                        let suggestion = store.suggestedSession()
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                DayTile(
                                    day: day,
                                    isSuggested: viewingWeek == suggestion.week && index == suggestion.dayIndex,
                                    isCompleted: completed.contains(index)
                                ) {
                                    onSelectDay(index, viewingWeek)
                                }
                                // Feature request — "there needs to be a way to delete... workouts
                                // within the week... hold and delete function much like iOS." Only
                                // this viewed week is affected; hidden when it's the last day left.
                                .contextMenu {
                                    if days.count > 1 {
                                        Button("Delete Workout", role: .destructive) {
                                            store.removeDay(atIndex: index, forWeek: viewingWeek)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("This Week")
        .navigationBarTitleDisplayMode(.inline)
        // Feature request — "I want users to be able to swipe left and right when they toggle
        // through the weeks." The chevrons above still work; this adds the swipe as another way
        // to trigger the same `shiftWeek`. A largish `minimumDistance` plus checking the drag is
        // more horizontal than vertical keeps this from fighting the ScrollView's own vertical
        // scroll gesture for the day tiles.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    shiftWeek(by: value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private func shiftWeek(by delta: Int) {
        manuallySelectedWeek = min(max(1, viewingWeek + delta), store.program.weekCount)
    }
}

private struct DayTile: View {
    let day: ProgramDay
    let isSuggested: Bool
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if isSuggested {
                        Text("SUGGESTED").font(ForgeType.label).foregroundStyle(Color.white.opacity(0.85))
                    }
                    Spacer()
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(isSuggested ? Color.white : ForgeColors.accent)
                    }
                }
                Text(day.name).font(ForgeType.body).foregroundStyle(isSuggested ? Color.white : ForgeColors.ink).lineLimit(2)
                Text("\(day.exercises.count) exercise\(day.exercises.count == 1 ? "" : "s")")
                    .font(ForgeType.caption).foregroundStyle(isSuggested ? Color.white.opacity(0.85) : ForgeColors.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
            .frame(height: 100, alignment: .topLeading)
            .background {
                isSuggested ? AnyView(ForgeColors.accent) : AnyView(Rectangle().fill(.ultraThinMaterial))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
