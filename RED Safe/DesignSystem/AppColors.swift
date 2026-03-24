import SwiftUI
import UIKit

/// Crystal Clean Design System - Colors
/// 
/// A modern, airy palette with subtle gradients and high contrast for readability.
extension Color {
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    // MARK: - Core Backgrounds
    
    /// Main app background.
    /// Light: Very soft off-white/blue tint. Dark: Deep, rich midnight blue (not pitch black).
    static let appBackground = adaptive(
        light: UIColor(red: 250/255, green: 251/255, blue: 255/255, alpha: 1),
        dark: UIColor(red: 10/255, green: 14/255, blue: 28/255, alpha: 1)
    )

    /// Secondary background for sheets or modals.
    static let secondaryBackground = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 22/255, green: 27/255, blue: 45/255, alpha: 1)
    )

    // MARK: - Surfaces (Cards, Containers)

    /// Primary card background.
    /// Light: White with high opacity. Dark: Slightly lighter than bg.
    static let surface = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 30/255, green: 38/255, blue: 60/255, alpha: 1)
    )

    /// Subtle border or stroke for cards.
    static let border = adaptive(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.12)
    )

    // MARK: - Text

    /// Primary text (Titles, vital info).
    static let textPrimary = adaptive(
        light: UIColor(red: 26/255, green: 32/255, blue: 44/255, alpha: 1),
        dark: UIColor(red: 235/255, green: 240/255, blue: 255/255, alpha: 1)
    )

    /// Secondary text (Subtitles, captions).
    static let textSecondary = adaptive(
        light: UIColor(red: 113/255, green: 128/255, blue: 150/255, alpha: 1),
        dark: UIColor(red: 148/255, green: 163/255, blue: 184/255, alpha: 1)
    )
    
    /// Tertiary text (Placeholders, disabled).
    static let textTertiary = adaptive(
        light: UIColor.black.withAlphaComponent(0.3),
        dark: UIColor.white.withAlphaComponent(0.3)
    )

    // MARK: - Accents (Brand)

    /// Primary Brand Color (Vibrant Blue).
    static let primaryBrand = Color(red: 59/255, green: 130/255, blue: 246/255) // #3B82F6
    
    /// Secondary Brand Color (Softer Blue).
    static let secondaryBrand = Color(red: 96/255, green: 165/255, blue: 250/255) // #60A5FA

    /// A nice gradient for primary actions.
    static let primaryGradient = LinearGradient(
        colors: [Color(red: 37/255, green: 99/255, blue: 235/255), Color(red: 59/255, green: 130/255, blue: 246/255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Functional

    static let successGreen = Color(red: 34/255, green: 197/255, blue: 94/255) // #22C55E
    static let errorRed = Color(red: 239/255, green: 68/255, blue: 68/255) // #EF4444
    static let warningOrange = Color(red: 245/255, green: 158/255, blue: 11/255) // #F59E0B
    
    // MARK: - Shadows
    
    static let shadowSubtle = adaptive(
        light: UIColor.black.withAlphaComponent(0.05),
        dark: UIColor.black.withAlphaComponent(0.3)
    )
    
    static let shadowStrong = adaptive(
        light: UIColor.black.withAlphaComponent(0.12),
        dark: UIColor.black.withAlphaComponent(0.5)
    )
}
