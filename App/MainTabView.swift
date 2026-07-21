import SwiftUI

enum MainTab: Hashable {
    case today, train, eat, progress, you
}

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @State private var selectedTab: MainTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(selectedTab: $selectedTab)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(MainTab.today)
            TrainView()
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
                .tag(MainTab.train)
            EatView()
                .tabItem { Label("Eat", systemImage: "fork.knife") }
                .tag(MainTab.eat)
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(MainTab.progress)
            YouView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(MainTab.you)
        }
        .tint(ForgeColors.accent)
        .onChange(of: scenePhase) { phase in
            // FRG-306 — re-evaluate tonight's reminders whenever the app backgrounds, so a
            // reminder already satisfied earlier today never re-fires after a stale schedule.
            if phase == .background, remindersEnabled { store.refreshReminders() }
            // FRG-114 — catches the case where the app was force-quit while offline: network
            // restore alone can't trigger a flush if nothing was running to observe it, so also
            // flush whenever the app comes back to the foreground.
            if phase == .active { Task { await SyncQueue.shared.flush() } }
        }
    }
}
