import Foundation

/// Feature request — "place a referral wall on the lift progression section... send the link out
/// to one person in order to unlock this feature, if that person signs up, unlock this feature."
/// No account system exists (Sign in with Apple is disconnected, CloudKit is per-iCloud-account
/// private data), so codes are generated client-side and redemption state lives in the FoodProxy
/// backend already deployed for FatSecret (`FoodProxy/server.js`'s `/referral` endpoints) rather
/// than standing up a new service. Not wired to a real tappable deep link yet — the app isn't on
/// TestFlight/App Store, so there's nowhere for a link to actually open. The "link" for now is a
/// shareable invite code the referred person types in at the end of onboarding.
@MainActor
final class ReferralManager: ObservableObject {
    static let shared = ReferralManager()

    private static let codeKey = "referralMyCode"
    private static let unlockedKey = "liftProgressionUnlocked"

    @Published private(set) var myCode: String
    @Published private(set) var isUnlocked: Bool {
        didSet { UserDefaults.standard.set(isUnlocked, forKey: Self.unlockedKey) }
    }
    @Published private(set) var isCheckingStatus = false

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        if let existing = UserDefaults.standard.string(forKey: Self.codeKey) {
            myCode = existing
        } else {
            let generated = Self.randomCode()
            myCode = generated
            UserDefaults.standard.set(generated, forKey: Self.codeKey)
        }
        // TEMPORARY — "unlock lift progression for now so I can test it." Forces the gate open
        // regardless of the persisted redemption flag. Revert this line (back to
        // `UserDefaults.standard.bool(forKey: Self.unlockedKey)`) before real launch, or the
        // referral wall never actually gates anything.
        isUnlocked = true
    }

    var shareMessage: String {
        "I'm using Trakt to track my lifts and nutrition — join me! Download the app, then enter invite code \(myCode) when you finish setting up your profile."
    }

    // Excludes 0/O/1/I so a typed-in code from a text message isn't ambiguous.
    private static func randomCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    /// Called once, when a newly onboarded user has entered someone else's invite code.
    func redeem(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let baseURL = Secrets.fatSecretProxyBaseURL,
              let secret = Secrets.fatSecretProxySharedSecret,
              let url = URL(string: "\(baseURL)/referral/redeem") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(secret, forHTTPHeaderField: "X-App-Secret")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["code": trimmed])

        _ = try? await session.data(for: request)
    }

    /// Polled from Progress whenever the Lift Progression section is shown and still locked.
    func refreshStatus() async {
        guard !isUnlocked,
              let baseURL = Secrets.fatSecretProxyBaseURL,
              let secret = Secrets.fatSecretProxySharedSecret else { return }

        var components = URLComponents(string: "\(baseURL)/referral/status")!
        components.queryItems = [URLQueryItem(name: "code", value: myCode)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue(secret, forHTTPHeaderField: "X-App-Secret")

        isCheckingStatus = true
        defer { isCheckingStatus = false }

        guard let (data, _) = try? await session.data(for: request),
              let decoded = try? JSONDecoder().decode(StatusResponse.self, from: data) else { return }
        if decoded.redeemed { isUnlocked = true }
    }

    private struct StatusResponse: Decodable { var redeemed: Bool }
}
