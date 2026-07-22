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
    // Re-wired for launch — was disconnected earlier this session only because the missing
    // DEVELOPMENT_TEAM (see project.yml) made Automatic signing fail on Simulator too; now that
    // team is set, this no longer blocks Simulator builds the way it did before.
    @StateObject private var signIn = AppleSignInManager.shared
    @State private var isRefreshingSignIn = true
    @State private var store: AppStore?
    @State private var isLoadingProfile = true

    var body: some View {
        Group {
            if isRefreshingSignIn {
                ZStack {
                    ForgeColors.backgroundWash
                    ProgressView()
                }
            } else if !signIn.isSignedIn {
                SignInView()
            } else if isLoadingProfile {
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
            // Re-validated against Apple's servers, not just a locally-cached flag — catches a
            // sign-in revoked from Apple ID settings since last launch.
            await signIn.refreshSignInState()
            isRefreshingSignIn = false
        }
        // Bug fix — this used to be an unconditional `.task` that fired at launch in parallel
        // with the Sign in with Apple check above, not waiting on it. On a fresh reinstall, that
        // race could resolve (fail or return nil) *before* the user finished signing in, which
        // permanently decided "show onboarding" — CloudKit never got a real chance once the user
        // had actually authenticated. `.task(id:)` re-runs whenever `signIn.isSignedIn` changes,
        // so the fetch only ever happens once sign-in is confirmed, and happens again right after
        // a fresh sign-in on a reinstalled app rather than relying on a stale earlier attempt.
        .task(id: signIn.isSignedIn) {
            guard signIn.isSignedIn else { return }
            isLoadingProfile = true
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
