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
    // Bug fix — this used to be applied only on YouView's own subtree, which does two things
    // wrong: it never touches the other four tabs at all (a `.preferredColorScheme` modifier only
    // affects the view it's attached to and its descendants), and it doesn't reliably override the
    // raw `UIColor` dynamic providers `ForgeColors` uses (those resolve off the actual UIWindow's
    // trait collection, which only a root-level override reliably updates). The toggle looked
    // "perpetually dark" because it was actually just following the Simulator's own system
    // appearance the whole time. Applying it once here, at the true root, fixes both. Also
    // switched from `.dark : nil` (dark vs "follow system") to `.dark : .light` — a single on/off
    // toggle labeled "Dark Mode" reads as an explicit override in both directions, not
    // dark-vs-system.
    @AppStorage("forceDarkMode") private var forceDarkMode = false
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
        .preferredColorScheme(forceDarkMode ? .dark : .light)
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

// Sign in with Apple (AppleSignInManager.swift / SignInView.swift) — built, deliberately
// disconnected from RootView for now: it was blocking Simulator testing (see git history for the
// signing/provisioning saga). Re-wire the gate above once ready to launch: `@StateObject private
// var signIn = AppleSignInManager.shared`, show `SignInView()` while `!signIn.isSignedIn`, and
// re-add the `com.apple.developer.applesignin` entitlement to project.yml.
