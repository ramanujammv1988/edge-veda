/**
 * Centralized premium theme constants for the Veda app.
 * True black background with teal/cyan accent palette.
 * Matches the Flutter example app exactly.
 */
export const AppTheme = {
  // Core Colors
  background: '#000000',
  surface: '#0A0A0F',
  surfaceVariant: '#141420',
  accent: '#00BCD4',
  accentDim: '#00838F',

  // Text Colors
  textPrimary: '#F5F5F5',
  textSecondary: '#8A8A9A',
  textTertiary: '#5A5A6A',

  // UI Element Colors
  border: '#1E1E2E',
  userBubble: '#00838F',
  assistantBubble: '#0A0A0F',

  // Brand Colors
  brandRed: '#E50914',

  // Status Colors
  danger: '#EF5350',
  success: '#66BB6A',
  warning: '#FFB74D',
} as const;