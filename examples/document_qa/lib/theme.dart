import 'package:flutter/material.dart';

/// App theme with blue accent on true-black background.
///
/// Designed for a clean, professional document Q&A experience.
class AppTheme {
  AppTheme._();

  // -- Core Colors -----------------------------------------------------------

  /// True black background
  static const Color background = Color(0xFF000000);

  /// Dark card/surface color
  static const Color surface = Color(0xFF121212);

  /// Slightly elevated surface
  static const Color surfaceVariant = Color(0xFF1E1E1E);

  /// Blue primary accent
  static const Color accent = Color(0xFF42A5F5); // Colors.blue.shade400

  /// Darker blue for pressed/secondary
  static const Color accentDark = Color(0xFF1E88E5); // Colors.blue.shade600

  // -- Text Colors -----------------------------------------------------------

  /// Primary text (white)
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary text (grey)
  static const Color textSecondary = Color(0xFFBDBDBD); // Colors.grey.shade400

  /// Tertiary/hint text
  static const Color textTertiary = Color(0xFF757575); // Colors.grey.shade600

  // -- UI Element Colors -----------------------------------------------------

  /// User message bubble
  static const Color userBubble = Color(0xFF1E88E5);

  /// Assistant message bubble
  static const Color assistantBubble = Color(0xFF1E1E1E);

  /// Subtle border
  static const Color border = Color(0xFF2C2C2C);

  // -- ThemeData -------------------------------------------------------------

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
        onPrimary: Colors.white,
        error: Color(0xFFEF5350),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textPrimary),
        labelSmall: TextStyle(fontSize: 11, color: textTertiary),
      ),
    );
  }
}
