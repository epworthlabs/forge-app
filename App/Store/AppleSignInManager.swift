import Foundation
import AuthenticationServices

/// Feature request — "implement a sign up flow via... apple." Deliberately Apple-only: this
/// app's whole data layer lives in CloudKit's private database, which is already scoped to
/// whatever Apple ID the device is signed into — Sign in with Apple formalizes an identity that
/// effectively already exists, rather than requiring a second backend the way Google/email would
/// (CloudKit has no concept of signing in with a non-Apple identity).
@MainActor
final class AppleSignInManager: ObservableObject {
    static let shared = AppleSignInManager()

    private static let userIDKey = "appleSignInUserID"

    @Published private(set) var isSignedIn = false

    private init() {}

    private var storedUserID: String? {
        UserDefaults.standard.string(forKey: Self.userIDKey)
    }

    func completeSignIn(userID: String) {
        UserDefaults.standard.set(userID, forKey: Self.userIDKey)
        isSignedIn = true
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.userIDKey)
        isSignedIn = false
    }

    /// Re-validates a previously stored sign-in against Apple's servers on launch — catches the
    /// case where the user revoked the app's access from their Apple ID settings since last time,
    /// which a purely local "did we sign in once" flag would never notice on its own.
    func refreshSignInState() async {
        guard let userID = storedUserID else {
            isSignedIn = false
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        let state: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
        isSignedIn = (state == .authorized)
    }
}
