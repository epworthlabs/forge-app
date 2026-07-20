import SwiftUI
import UIKit

/// "Liquid Glass" — the design direction the style exploration converged on (see
/// `../../../Wireframes/updated/uploads/Fitness and nutrition tracker app/`: TodayGlassLight.dc.html
/// / TodayGlassDark.dc.html, refined from the "Fitness Tracker App.dc.html" full-flow reference).
/// Values are exact sRGB conversions of that file's oklch tokens (oklch has no native SwiftUI
/// representation on iOS 16, so these were computed via the standard OKLab→linear-sRGB→sRGB
/// matrices rather than eyeballed) — token names below mirror the design file's CSS custom
/// properties 1:1 for traceability.
enum ForgeColors {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func hex(_ hex: String, alpha: CGFloat = 1) -> UIColor {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                        blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }

    static let ink = dynamic(light: hex("#11161F"), dark: hex("#EAEFF5"))
    static let inkMuted = dynamic(light: hex("#4C5666"), dark: hex("#8291A1"))

    static let accent = dynamic(light: hex("#156CDD"), dark: hex("#569DFF"))
    static let accent2 = dynamic(light: hex("#00A281"), dark: hex("#00B294"))
    static let accent3 = dynamic(light: hex("#AE96DA"), dark: hex("#B6A1DF"))

    static let cardBackground = dynamic(light: hex("#FFFFFF", alpha: 0.45), dark: hex("#343B45", alpha: 0.35))
    static let cardBorder = dynamic(light: hex("#FFFFFF", alpha: 0.65), dark: hex("#FFFFFF", alpha: 0.14))
    static let cardShadow = dynamic(light: hex("#283B5A", alpha: 0.12), dark: hex("#000000", alpha: 0.4))
    static let cardHighlight = dynamic(light: hex("#FFFFFF", alpha: 0.6), dark: hex("#FFFFFF", alpha: 0.08))

    static let tileBackground = dynamic(light: hex("#FFFFFF", alpha: 0.5), dark: hex("#FFFFFF", alpha: 0.08))
    static let tileBorder = dynamic(light: hex("#FFFFFF", alpha: 0.5), dark: hex("#FFFFFF", alpha: 0.1))
    static let trackBackground = dynamic(light: hex("#FFFFFF", alpha: 0.5), dark: hex("#FFFFFF", alpha: 0.1))

    static let ringTrack = dynamic(light: hex("#FFFFFF", alpha: 0.35), dark: hex("#FFFFFF", alpha: 0.12))
    static let ringFillBackground = dynamic(light: hex("#F4F9FF", alpha: 0.9), dark: hex("#11161F", alpha: 0.9))

    static let avatarBackground = dynamic(light: hex("#FFFFFF", alpha: 0.55), dark: hex("#414853", alpha: 0.4))
    static let avatarBorder = dynamic(light: hex("#FFFFFF", alpha: 0.7), dark: hex("#FFFFFF", alpha: 0.15))

    static let tabbarBackground = dynamic(light: hex("#FFFFFF", alpha: 0.55), dark: hex("#343B45", alpha: 0.45))
    static let tabbarBorder = dynamic(light: hex("#FFFFFF", alpha: 0.7), dark: hex("#FFFFFF", alpha: 0.16))
    static let tabbarInactiveIcon = dynamic(light: hex("#FFFFFF", alpha: 0.5), dark: hex("#FFFFFF", alpha: 0.12))
    static let tabbarTextActive = dynamic(light: hex("#1F2E47"), dark: hex("#D4DFEB"))
    static let tabbarTextInactive = dynamic(light: hex("#5D646F"), dark: hex("#86909B"))

    static let switchTrackOff = dynamic(light: hex("#CACED4"), dark: hex("#45484D"))
    static var switchTrackOn: Color { accent }

    static let backgroundBase = dynamic(light: hex("#E4ECF5"), dark: hex("#04080D"))

    /// The three-stop radial-gradient wash behind every Liquid Glass screen.
    static var backgroundWash: some View {
        ZStack {
            backgroundBase
            dynamic(light: hex("#F6CDFF", alpha: 0.9), dark: hex("#3F1E46", alpha: 0.9))
                .mask(RadialGradient(colors: [.black, .clear], center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 340))
            dynamic(light: hex("#92F1F6", alpha: 0.85), dark: hex("#003147", alpha: 0.85))
                .mask(RadialGradient(colors: [.black, .clear], center: UnitPoint(x: 1.0, y: 0.15), startRadius: 0, endRadius: 320))
            dynamic(light: hex("#B0DCFF", alpha: 0.9), dark: hex("#022544", alpha: 0.9))
                .mask(RadialGradient(colors: [.black, .clear], center: UnitPoint(x: 0.2, y: 1.0), startRadius: 0, endRadius: 380))
        }
        .ignoresSafeArea()
    }
}
