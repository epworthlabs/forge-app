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
    // of 12." nil means "just show the real current week" — avoids needing `store` (an
    // @EnvironmentObject, not available yet inside init) to seed this at construction time; only
    // set once the user actually pages away from the current week.
    @State private var manuallySelectedWeek: Int?
    private var viewingWeek: Int { manuallySelectedWeek ?? store.currentProgramWeek }

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.program.name).font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
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
                        // already been done." Suggestion only makes sense for the real current
                        // week — browsing a different week is for reference, not "what's next."
                        let completed = store.completedDayIndices(forWeek: viewingWeek)
                        let suggested = store.suggestedDayIndex(forWeek: viewingWeek)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                DayTile(
                                    day: day,
                                    isSuggested: viewingWeek == store.currentProgramWeek && index == suggested,
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
