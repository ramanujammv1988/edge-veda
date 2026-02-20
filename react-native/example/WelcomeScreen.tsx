import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Dimensions } from 'react-native';
import Svg, { Path, Defs, RadialGradient, Stop, Circle as SvgCircle } from 'react-native-svg';
import { AppTheme } from './theme';

const { width } = Dimensions.get('window');

interface WelcomeScreenProps {
  onGetStarted: () => void;
}

/**
 * Premium onboarding/welcome screen with bold red "V" branding.
 *
 * Matches the Flutter WelcomeScreen pixel-for-pixel:
 * - Radial red glow behind the "V" logo
 * - Bold red "V" (Netflix-style) on true black background
 * - "Veda" title with subtle letter spacing
 * - "On-Device Intelligence" subtitle
 * - Teal "Get Started" pill button
 * - "100% Private" tagline
 */
export function WelcomeScreen({ onGetStarted }: WelcomeScreenProps): React.JSX.Element {
  return (
    <View style={styles.container}>
      {/* Bold red "V" with radial glow */}
      <View style={styles.logoContainer}>
        <Svg width={200} height={200} viewBox="0 0 200 200">
          <Defs>
            <RadialGradient id="glow" cx="100" cy="100" r="120">
              <Stop offset="0" stopColor={AppTheme.brandRed} stopOpacity="0.15" />
              <Stop offset="1" stopColor={AppTheme.brandRed} stopOpacity="0" />
            </RadialGradient>
          </Defs>
          <SvgCircle cx="100" cy="100" r="100" fill="url(#glow)" />
          <Path
            d="M 53 30 L 78 30 L 100 120 L 122 30 L 147 30 L 100 170 Z"
            fill={AppTheme.brandRed}
          />
        </Svg>
      </View>

      {/* App name */}
      <Text style={styles.title}>Veda</Text>

      {/* Subtitle */}
      <Text style={styles.subtitle}>On-Device Intelligence</Text>

      {/* "Get Started" button — teal pill */}
      <TouchableOpacity style={styles.button} onPress={onGetStarted} activeOpacity={0.8}>
        <Text style={styles.buttonText}>Get Started</Text>
      </TouchableOpacity>

      {/* Privacy tagline */}
      <Text style={styles.tagline}>100% Private. Runs entirely on your device.</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: AppTheme.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoContainer: {
    width: 200,
    height: 200,
    marginBottom: 32,
  },
  title: {
    fontSize: 36,
    fontWeight: '700',
    color: AppTheme.textPrimary,
    letterSpacing: 4,
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 16,
    color: AppTheme.textSecondary,
    marginBottom: 48,
  },
  button: {
    width: Math.min(280, width - 80),
    height: 56,
    borderRadius: 28,
    backgroundColor: AppTheme.accent,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 24,
  },
  buttonText: {
    fontSize: 18,
    fontWeight: '700',
    color: AppTheme.background,
  },
  tagline: {
    fontSize: 12,
    color: AppTheme.textTertiary,
    textAlign: 'center',
  },
});