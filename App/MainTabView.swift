import SwiftUI

enum MainTab: Hashable {
    case today, train, eat, progress, you
}

struct MainTabView: View {
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
    }
}
