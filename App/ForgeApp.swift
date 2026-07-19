import SwiftUI
import ForgeCore

@main
struct ForgeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var store: AppStore?

    var body: some View {
        if let store {
            MainTabView()
                .environmentObject(store)
        } else {
            OnboardingView { profile, program in
                store = AppStore(profile: profile, program: program)
            }
        }
    }
}
