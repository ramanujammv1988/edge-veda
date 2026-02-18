import SwiftUI

/// Centralized premium theme constants for the Veda app.
/// True black background with teal/cyan accent palette.
/// Matches the Flutter example app exactly.
enum AppTheme {
    // MARK: - Core Colors
    
    /// True black background
    static let background = Color(hex: 0x000000)
    
    /// Near-black for cards/surfaces
    static let surface = Color(hex: 0x0A0A0F)
    
    /// Slightly lighter surface for elevated elements
    static let surfaceVariant = Color(hex: 0x141420)
    
    /// Teal/cyan primary accent
    static let accent = Color(hex: 0x00BCD4)
    
    /// Dimmed teal for secondary elements
    static let accentDim = Color(hex: 0x00838F)
    
    /// Radial glow color (teal with low opacity)
    static let accentGlow = Color(hex: 0x00BCD4).opacity(0.15)
    
    // MARK: - Text Colors
    
    /// Near-white for primary text
    static let textPrimary = Color(hex: 0xF5F5F5)
    
    /// Muted for secondary text
    static let textSecondary = Color(hex: 0x8A8A9A)
    
    /// Very muted for hints
    static let textTertiary = Color(hex: 0x5A5A6A)
    
    // MARK: - UI Element Colors
    
    /// Subtle borders
    static let border = Color(hex: 0x1E1E2E)
    
    /// Teal-tinted user message bubble
    static let userBubble = Color(hex: 0x00838F)
    
    /// Dark surface for assistant message bubble
    static let assistantBubble = Color(hex: 0x0A0A0F)
    
    // MARK: - Brand Colors
    
    /// Netflix-style bold red for "V" logo/branding
    static let brandRed = Color(hex: 0xE50914)
    
    // MARK: - Status Colors
    
    /// Error/stop
    static let danger = Color(hex: 0xEF5350)
    
    /// Success states
    static let success = Color(hex: 0x66BB6A)
    
    /// Warnings
    static let warning = Color(hex: 0xFFB74D)
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}