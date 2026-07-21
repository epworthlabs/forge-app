import SwiftUI
import ForgeCore

/// Feature request — shown after picking a program, and again after Finish Workout (item 3: "bring
/// them to another screen where users can either review the workout they just did or select a
/// different workout from that week"). The day Finish Workout just rotated to is highlighted as
/// the suggested next session; a review tile appears only while there's something to review.
struct DaySelectionView: View {
    @EnvironmentObject var store: AppStore
    var onSelectDay: (Int) -> Void
    var onReview: () -> Void

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.program.name).font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                        Text("Week \(store.currentProgramWeek) of \(store.program.weekCount)").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
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

                    Text("This week").font(ForgeType.label).foregroundStyle(ForgeColors.inkMuted)
                    let days = store.program.days(forWeek: store.currentProgramWeek)
                    if days.isEmpty {
                        Text("This program doesn't have any days set up yet.").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                DayTile(day: day, isSuggested: index == store.currentProgramDayIndex) {
                                    onSelectDay(index)
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
}

private struct DayTile: View {
    let day: ProgramDay
    let isSuggested: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                if isSuggested {
                    Text("SUGGESTED").font(ForgeType.label).foregroundStyle(Color.white.opacity(0.85))
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
