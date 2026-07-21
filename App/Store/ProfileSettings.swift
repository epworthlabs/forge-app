import Foundation

/// Feature request — "give a default avatar and assign a randomly generated username at the top.
/// Let users edit those two fields if they want." Local-only (UserDefaults), same tier as
/// forceDarkMode/restDurationSeconds — this is presentation, not the core domain data CloudKit
/// already handles for profile/training/nutrition.
@MainActor
final class ProfileSettings: ObservableObject {
    static let shared = ProfileSettings()

    private static let usernameKey = "profileUsername"
    private static let avatarKey = "profileAvatarData"

    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Self.usernameKey) }
    }
    @Published var avatarImageData: Data? {
        didSet { UserDefaults.standard.set(avatarImageData, forKey: Self.avatarKey) }
    }

    private init() {
        if let existing = UserDefaults.standard.string(forKey: Self.usernameKey) {
            username = existing
        } else {
            let generated = Self.randomUsername()
            username = generated
            UserDefaults.standard.set(generated, forKey: Self.usernameKey)
        }
        avatarImageData = UserDefaults.standard.data(forKey: Self.avatarKey)
    }

    private static func randomUsername() -> String {
        let adjectives = ["Swift", "Iron", "Steel", "Quiet", "Bold", "Rapid", "Solid", "Prime", "Wild", "Calm", "Sharp", "Lean"]
        let nouns = ["Lifter", "Athlete", "Runner", "Climber", "Grinder", "Warrior", "Falcon", "Tiger", "Wolf", "Ranger"]
        return "\(adjectives.randomElement()!)\(nouns.randomElement()!)\(Int.random(in: 10...99))"
    }
}
