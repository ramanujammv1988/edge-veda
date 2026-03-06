package com.edgeveda.example

import androidx.compose.ui.graphics.Color

/**
 * Centralized premium theme constants for the Veda app.
 * True black background with teal/cyan accent palette.
 * Matches the Flutter example app exactly.
 */
object AppTheme {
    // Core Colors
    val background = Color(0xFF000000)
    val surface = Color(0xFF0A0A0F)
    val surfaceVariant = Color(0xFF141420)
    val accent = Color(0xFF00BCD4)
    val accentDim = Color(0xFF00838F)

    // Text Colors
    val textPrimary = Color(0xFFF5F5F5)
    val textSecondary = Color(0xFF8A8A9A)
    val textTertiary = Color(0xFF5A5A6A)

    // UI Element Colors
    val border = Color(0xFF1E1E2E)
    val userBubble = Color(0xFF00838F)
    val assistantBubble = Color(0xFF0A0A0F)

    // Brand Colors
    val brandRed = Color(0xFFE50914)

    // Status Colors
    val danger = Color(0xFFEF5350)
    val success = Color(0xFF66BB6A)
    val warning = Color(0xFFFFB74D)
}