import SwiftUI
import AuthenticationServices

/// Feature request — "implement a sign up flow via... apple." Shown before onboarding/CloudKit
/// fetch in RootView whenever there's no valid stored sign-in. Redesigned per Desktop/Design.pdf:
/// a fixed brand-blue full-bleed gradient (doesn't follow system/forced dark mode — this is a
/// branded splash, not a themed app screen), the ring mark with its own background stripped out
/// (`AppMarkTransparent` — see the asset's generation notes) so it sits directly on the gradient,
/// and only "Continue with Apple" — the mockup's "Continue with email" was explicitly dropped.
struct SignInView: View {
    @ObservedObject private var manager = AppleSignInManager.shared
    @State private var errorMessage: String?

    // Sampled directly from the design mockup (top/bottom of the phone screen area), not guessed.
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 36.0 / 255, green: 139.0 / 255, blue: 213.0 / 255),
            Color(red: 14.0 / 255, green: 52.0 / 255, blue: 116.0 / 255),
        ],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        ZStack {
            Self.gradient.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()
                Image("AppMarkTransparent")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                Text("TRAKT")
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(6)
                    .foregroundStyle(.white)
                Spacer()

                if let errorMessage {
                    Text(errorMessage).font(ForgeType.caption).foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                        // RootView holds the same shared manager instance, so flipping
                        // `isSignedIn` here is what drives it past this screen — no callback needed.
                        manager.completeSignIn(userID: credential.user)
                    case .failure(let error):
                        // ASAuthorizationError.canceled fires every time the user just dismisses
                        // the sheet — not a real error worth surfacing.
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            errorMessage = "Sign in failed — try again."
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)

                legalFooter
                    .padding(.top, 4)
                    .padding(.bottom, 40)
            }
        }
    }

    // "Terms" has no real page yet (unlike Privacy Policy, which is live) — styled to match but
    // deliberately not a tappable Link, rather than wiring it to a page that doesn't exist.
    private var legalFooter: some View {
        (
            Text("By continuing, you agree to our ")
                + Text("Terms").foregroundColor(.white.opacity(0.85))
                + Text(" and ")
                + Text("[Privacy Policy](https://forge-food-proxy.onrender.com/privacy)")
        )
        .font(ForgeType.caption)
        .foregroundColor(.white.opacity(0.6))
        .tint(.white.opacity(0.85))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }
}
