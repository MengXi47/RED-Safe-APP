import SwiftUI

/// Crystal Clean Design System - Typography
/// 
/// Uses the system font (SF Pro) with specific weights and tracking for a polished look.
extension Font {
    
    // MARK: - Headers
    
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 22, weight: .semibold, design: .rounded)
    
    // MARK: - Body
    
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)
    
    // MARK: - Utility
    
    static let buttonText = Font.system(size: 17, weight: .semibold, design: .default)
    static let captionText = Font.system(size: 12, weight: .medium, design: .default)
}
