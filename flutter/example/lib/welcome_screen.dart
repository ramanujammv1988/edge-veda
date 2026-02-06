import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Premium onboarding/welcome screen with bold red "V" branding.
///
/// Shown on cold start before the main app. Displays:
/// - Radial red glow behind the "V" logo
/// - Bold red "V" (Netflix-style) on true black background
/// - "Veda" title with subtle letter spacing
/// - "On-Device Intelligence" subtitle
/// - Teal "Get Started" pill button
/// - "100% Private" tagline
class WelcomeScreen extends StatelessWidget {
  /// Callback invoked when the user taps "Get Started".
  final VoidCallback onGetStarted;

  const WelcomeScreen({super.key, required this.onGetStarted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Bold red "V" with radial glow
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Radial red glow behind logo
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.brandRed.withValues(alpha: 0.15),
                            Colors.transparent,
                          ],
                          radius: 0.6,
                        ),
                      ),
                    ),
                    // Bold red "V" — Netflix-style
                    Container(
                      width: 120,
                      height: 120,
                      alignment: Alignment.center,
                      child: const Text(
                        'V',
                        style: TextStyle(
                          fontSize: 96,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.brandRed,
                          letterSpacing: -4,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // App name
              const Text(
                'Veda',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: 4,
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              const Text(
                'On-Device Intelligence',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                ),
              ),

              const SizedBox(height: 48),

              // "Get Started" button — teal pill
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: onGetStarted,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'Get Started',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Privacy tagline
              const Text(
                '100% Private. Runs entirely on your device.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
