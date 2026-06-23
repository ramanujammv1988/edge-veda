import 'package:flutter/material.dart';

/// Centralized theme for the Medical Interpreter app.
///
/// Teal accent on true-black background, with role-specific colors
/// for provider (blue) and patient (green) conversation sides.
class AppTheme {
  AppTheme._();

  // -- Core Colors --------------------------------------------------------

  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceVariant = Color(0xFF1E1E1E);

  /// Teal primary accent
  static final Color accent = Colors.teal.shade400;
  static final Color accentDark = Colors.teal.shade700;

  // -- Text Colors --------------------------------------------------------

  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFF8A8A9A);
  static const Color textTertiary = Color(0xFF5A5A6A);

  // -- UI Element Colors --------------------------------------------------

  static const Color border = Color(0xFF2A2A2A);
  static const Color danger = Color(0xFFEF5350);

  // -- Role Colors --------------------------------------------------------

  /// Provider side (blue tint)
  static final Color providerBubble = Colors.blue.shade800;
  static final Color providerAccent = Colors.blue.shade300;

  /// Patient side (green tint)
  static final Color patientBubble = Colors.teal.shade800;
  static final Color patientAccent = Colors.teal.shade300;

  // -- ThemeData ----------------------------------------------------------

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.dark(
        surface: surface,
        primary: accent,
        secondary: accentDark,
        onSurface: textPrimary,
        onPrimary: background,
        error: Colors.red.shade400,
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
          foregroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: textPrimary),
      ),
    );
  }
}
