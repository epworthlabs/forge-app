import SwiftUI
import UIKit

/// Approximated from the hi-fi prototype's oklch tokens (Fitness Tracker App.dc.html). Precision
/// wasn't critical for a pre-Xcode scaffold — re-check these against the prototype in Simulator
/// once it's buildable, then promote to a proper Asset Catalog.
enum ForgeColors {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let ink = dynamic(light: UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1),
                              dark: UIColor(red: 0.93, green: 0.93, blue: 0.91, alpha: 1))
    static let inkMuted = dynamic(light: UIColor(red: 0.36, green: 0.38, blue: 0.42, alpha: 1),
                                   dark: UIColor(red: 0.65, green: 0.66, blue: 0.69, alpha: 1))

    static let accent = dynamic(light: UIColor(red: 0.24, green: 0.44, blue: 0.90, alpha: 1),
                                 dark: UIColor(red: 0.48, green: 0.63, blue: 0.94, alpha: 1))
    static let accent2 = dynamic(light: UIColor(red: 0.18, green: 0.66, blue: 0.57, alpha: 1),
                                  dark: UIColor(red: 0.37, green: 0.76, blue: 0.67, alpha: 1))
    static let accent3 = dynamic(light: UIColor(red: 0.72, green: 0.59, blue: 0.84, alpha: 1),
                                  dark: UIColor(red: 0.79, green: 0.68, blue: 0.87, alpha: 1))

    static let cardBackground = dynamic(light: UIColor.white.withAlphaComponent(0.45),
                                         dark: UIColor(red: 0.21, green: 0.22, blue: 0.25, alpha: 0.35))
    static let cardBorder = dynamic(light: UIColor.white.withAlphaComponent(0.65),
                                     dark: UIColor.white.withAlphaComponent(0.14))
    static let tileBackground = dynamic(light: UIColor.white.withAlphaComponent(0.5),
                                         dark: UIColor.white.withAlphaComponent(0.08))
    static let trackBackground = dynamic(light: UIColor.white.withAlphaComponent(0.5),
                                          dark: UIColor.white.withAlphaComponent(0.1))

    static let backgroundBase = dynamic(light: UIColor(red: 0.94, green: 0.945, blue: 0.965, alpha: 1),
                                         dark: UIColor(red: 0.075, green: 0.08, blue: 0.09, alpha: 1))
}
