import SwiftUI
import ForgeCore
import PostHog

@main
struct ForgeApp: App {
    init() {
        if let apiKey = Secrets.postHogAPIKey, !apiKey.isEmpty {
            let config = PostHogConfig(projectToken: apiKey, host: Secrets.postHogHost)
            PostHogSDK.shared.setup(config)
        }
    }

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
