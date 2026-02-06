import 'package:flutter/material.dart';

/// Centralized premium theme constants for the Veda app.
///
/// True black background with teal/cyan accent palette.
/// Used across all screens for consistent visual identity.
class AppTheme {
  AppTheme._();

  // ── Core Colors ──────────────────────────────────────────────────────────

  /// True black background
  static const Color background = Color(0xFF000000);

  /// Near-black for cards/surfaces
  static const Color surface = Color(0xFF0A0A0F);

  /// Slightly lighter surface for elevated elements
  static const Color surfaceVariant = Color(0xFF141420);

  /// Teal/cyan primary accent
  static const Color accent = Color(0xFF00BCD4);

  /// Dimmed teal for secondary elements
  static const Color accentDim = Color(0xFF00838F);

  /// Radial glow color (teal with low opacity)
  static Color get accentGlow => const Color(0xFF00BCD4).withValues(alpha: 0.15);

  // ── Text Colors ──────────────────────────────────────────────────────────

  /// Near-white for primary text
  static const Color textPrimary = Color(0xFFF5F5F5);

  /// Muted for secondary text
  static const Color textSecondary = Color(0xFF8A8A9A);

  /// Very muted for hints
  static const Color textTertiary = Color(0xFF5A5A6A);

  // ── UI Element Colors ────────────────────────────────────────────────────

  /// Subtle borders
  static const Color border = Color(0xFF1E1E2E);

  /// Teal-tinted user message bubble
  static const Color userBubble = Color(0xFF00838F);

  /// Dark surface for assistant message bubble
  static const Color assistantBubble = Color(0xFF0A0A0F);

  /// Pill indicator color for navigation
  static const Color navPill = Color(0xFF00BCD4);

  // ── Brand Colors ─────────────────────────────────────────────────────────

  /// Netflix-style bold red for "V" logo/branding
  static const Color brandRed = Color(0xFFE50914);

  // ── Status Colors ────────────────────────────────────────────────────────

  /// Error/stop
  static const Color danger = Color(0xFFEF5350);

  /// Success states
  static const Color success = Color(0xFF66BB6A);

  /// Warnings
  static const Color warning = Color(0xFFFFB74D);

  // ── ThemeData ────────────────────────────────────────────────────────────

  /// Full Material 3 ThemeData for the Veda app.
  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: accent,
        secondary: accentDim,
        onSurface: textPrimary,
        onPrimary: background,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        indicatorColor: accent.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accent);
          }
          return const IconThemeData(color: textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: textSecondary,
            fontSize: 12,
          );
        }),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textPrimary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          color: textTertiary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: textPrimary),
      ),
    );
  }
}
