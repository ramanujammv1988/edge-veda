import 'package:flutter/material.dart';

/// Centralized theme for the Voice Journal app.
///
/// Purple accent on true-black background.
class AppTheme {
  AppTheme._();

  // -- Core Colors --

  /// True black background
  static const Color background = Color(0xFF000000);

  /// Near-black for cards/surfaces
  static const Color surface = Color(0xFF121212);

  /// Slightly lighter surface for elevated elements
  static const Color surfaceVariant = Color(0xFF1E1E1E);

  /// Purple primary accent
  static const Color accent = Color(0xFFCE93D8); // Colors.purple.shade300

  /// Darker purple for secondary elements
  static const Color accentDark = Color(0xFF8E24AA); // Colors.purple.shade600

  /// Recording indicator red
  static const Color recording = Color(0xFFEF5350);

  // -- Text Colors --

  /// Near-white for primary text
  static const Color textPrimary = Color(0xFFF5F5F5);

  /// Muted for secondary text
  static const Color textSecondary = Color(0xFF9E9E9E);

  /// Very muted for hints
  static const Color textTertiary = Color(0xFF616161);

  // -- UI Element Colors --

  /// Subtle borders
  static const Color border = Color(0xFF2C2C2C);

  /// Success states
  static const Color success = Color(0xFF66BB6A);

  /// Error / danger
  static const Color danger = Color(0xFFEF5350);

  // -- ThemeData --

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: accent,
        secondary: accentDark,
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
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
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
      chipTheme: ChipThemeData(
        backgroundColor: accentDark.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: accent, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
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
