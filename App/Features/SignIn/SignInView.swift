import SwiftUI
import AuthenticationServices

/// Feature request — "implement a sign up flow via... apple." Shown before onboarding/CloudKit
/// fetch in RootView whenever there's no valid stored sign-in.
struct SignInView: View {
    @ObservedObject private var manager = AppleSignInManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 56)).foregroundStyle(ForgeColors.accent)
                VStack(spacing: 8) {
                    Text("Trakt").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                    Text("Sign in to get started").font(ForgeType.body).foregroundStyle(ForgeColors.inkMuted)
                }
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
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
        }
    }
}
