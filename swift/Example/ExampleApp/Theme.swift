//
//  Theme.swift
//  ExampleApp
//
//  EdgeVeda Example App Theme
//  Matches Flutter app color palette exactly
//

import SwiftUI

struct AppTheme {
    // MARK: - Core Colors
    static let background = Color(hex: "#000000")        // True black
    static let surface = Color(hex: "#0A0A0F")          // Near-black for cards
    static let surfaceVariant = Color(hex: "#141420")   // Elevated elements
    
    // MARK: - Accent Colors
    static let accent = Color(hex: "#00BCD4")           // Teal/cyan primary
    static let accentDim = Color(hex: "#00838F")        // Dimmed teal
    static let accentGlow = Color(hex: "#00BCD4").opacity(0.15) // Radial glow
    
    // MARK: - Text Colors
    static let textPrimary = Color(hex: "#F5F5F5")      // Near-white
    static let textSecondary = Color(hex: "#8A8A9A")    // Muted
    static let textTertiary = Color(hex: "#5A5A6A")     // Very muted
    
    // MARK: - UI Element Colors
    static let border = Color(hex: "#1E1E2E")           // Subtle borders
    static let userBubble = Color(hex: "#00838F")       // User message bubble
    static let assistantBubble = Color(hex: "#0A0A0F")  // Assistant bubble
    static let navPill = Color(hex: "#00BCD4")          // Nav indicator
    
    // MARK: - Brand Colors
    static let brandRed = Color(hex: "#E50914")         // Netflix-style red for "V" logo
    
    // MARK: - Status Colors
    static let danger = Color(hex: "#EF5350")           // Error/stop
    static let success = Color(hex: "#66BB6A")          // Success states
    static let warning = Color(hex: "#FFB74D")          // Warnings
    
    // MARK: - Typography
    struct Typography {
        static let headlineLarge = Font.system(size: 32, weight: .bold)
        static let titleLarge = Font.system(size: 22, weight: .semibold)
        static let bodyLarge = Font.system(size: 16, weight: .regular)
        static let bodyMedium = Font.system(size: 14, weight: .regular)
        static let labelSmall = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 11, weight: .regular)
    }
    
    // MARK: - Layout Constants
    struct Layout {
        static let cornerRadius: CGFloat = 12
        static let pillRadius: CGFloat = 28
        static let padding: CGFloat = 16
        static let smallPadding: CGFloat = 8
        static let largePadding: CGFloat = 24
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers
extension View {
    func appCard() -> some View {
        self
            .background(AppTheme.surface)
            .cornerRadius(AppTheme.Layout.cornerRadius)
    }
    
    func appButton() -> some View {
        self
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(AppTheme.accent)
            .foregroundColor(AppTheme.textPrimary)
            .cornerRadius(AppTheme.Layout.pillRadius)
    }
    
    func appSecondaryButton() -> some View {
        self
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(AppTheme.surface)
            .foregroundColor(AppTheme.accent)
            .cornerRadius(AppTheme.Layout.pillRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Layout.pillRadius)
                    .stroke(AppTheme.accent, lineWidth: 1)
            )
    }
}