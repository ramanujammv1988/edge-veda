import 'package:flutter/material.dart';

/// Centralized theme for the Health Advisor app.
///
/// Green accent on true-black background, with confidence-level colors
/// for the badge system (green/orange/red).
class AppTheme {
  AppTheme._();

  // -- Core Colors --------------------------------------------------------

  /// True black background
  static const Color background = Color(0xFF000000);

  /// Near-black card surface
  static const Color surface = Color(0xFF121212);

  /// Slightly lighter surface for elevated elements
  static const Color surfaceVariant = Color(0xFF1E1E1E);

  /// Green primary accent
  static final Color accent = Colors.green.shade400;

  /// Darker green for secondary elements
  static final Color accentDark = Colors.green.shade700;

  // -- Text Colors --------------------------------------------------------

  /// Near-white primary text
  static const Color textPrimary = Color(0xFFF5F5F5);

  /// Muted secondary text
  static const Color textSecondary = Color(0xFF8A8A9A);

  /// Very muted hint text
  static const Color textTertiary = Color(0xFF5A5A6A);

  // -- UI Element Colors --------------------------------------------------

  /// Subtle border
  static const Color border = Color(0xFF2A2A2A);

  /// User chat bubble (green)
  static final Color userBubble = Colors.green.shade700;

  /// Assistant chat bubble
  static const Color assistantBubble = Color(0xFF1E1E1E);

  // -- Confidence Colors --------------------------------------------------

  /// High confidence (>0.7)
  static final Color confidenceHigh = Colors.green.shade400;

  /// Medium confidence (0.4-0.7)
  static final Color confidenceMedium = Colors.orange.shade400;

  /// Low confidence (<0.4)
  static final Color confidenceLow = Colors.red.shade400;

  /// Get confidence color based on score
  static Color confidenceColor(double score) {
    if (score > 0.7) return confidenceHigh;
    if (score > 0.4) return confidenceMedium;
    return confidenceLow;
  }

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
          borderSide: BorderSide(color: accent),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: textPrimary),
      ),
    );
  }
}
