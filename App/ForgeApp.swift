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
    @State private var isLoadingProfile = true

    var body: some View {
        Group {
            if isLoadingProfile {
                ZStack {
                    ForgeColors.backgroundWash
                    ProgressView()
                }
            } else if let store {
                MainTabView()
                    .environmentObject(store)
            } else {
                OnboardingView { profile, program in
                    let startDate = Date()
                    let newStore = AppStore(profile: profile, program: program, programStartDate: startDate)
                    store = newStore
                    Task { await SyncQueue.shared.enqueue(.profile(profile: profile, program: program, savedPrograms: [program], dayIndex: 0, programStartDate: startDate)) }
                }
            }
        }
        .task {
            // FRG-130/131 — a returning user with a saved CloudKit profile skips onboarding
            // entirely; a brand-new user (or one without CloudKit access yet) sees it as before.
            if let (profile, program, savedPrograms, dayIndex, programStartDate) = try? await CloudKitStore.shared.fetchProfile() {
                let loadedStore = AppStore(profile: profile, program: program, savedPrograms: savedPrograms, startingDayIndex: dayIndex, programStartDate: programStartDate)
                await loadedStore.loadHistoryFromCloudKit()
                store = loadedStore
            }
            isLoadingProfile = false
        }
    }
}
