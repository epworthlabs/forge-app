import SwiftUI
import UIKit

/// The prototype specifies Inter throughout. Inter isn't a system font — it needs to be added to
/// the project (Google Fonts, OFL license) and registered in Info.plist's UIAppFonts before these
/// will render as anything but the system-font fallback below.
enum ForgeType {
    private static func inter(_ weight: String, _ size: CGFloat) -> Font {
        let name = "Inter-\(weight)"
        if UIFont(name: name, size: size) != nil {
            return Font.custom(name, size: size)
        }
        return .system(size: size, weight: systemWeight(for: weight))
    }

    private static func systemWeight(for weight: String) -> Font.Weight {
        switch weight {
        case "Bold", "ExtraBold": return .bold
        case "SemiBold": return .semibold
        case "Medium": return .medium
        default: return .regular
        }
    }

    static let displayLarge = inter("ExtraBold", 30)   // Today screen H1
    static let displayMedium = inter("Bold", 25)        // Onboarding step titles
    static let title = inter("Bold", 16)
    static let body = inter("SemiBold", 14)
    static let caption = inter("Medium", 12)
    static let label = inter("Bold", 11)
}
