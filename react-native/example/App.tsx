import React, { useState } from 'react';
import { SafeAreaView, StatusBar } from 'react-native';
import { AppTheme } from './theme';
import { WelcomeScreen } from './WelcomeScreen';
import { MainTabs } from './MainTabs';

/**
 * Edge Veda Example App — React Native
 *
 * A full demonstration app showcasing the Edge Veda SDK for on-device
 * LLM inference. Mirrors the Flutter example app's UI.
 */
export default function App(): React.JSX.Element {
  const [showWelcome, setShowWelcome] = useState(true);

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: AppTheme.background }}>
      <StatusBar barStyle="light-content" backgroundColor={AppTheme.background} />
      {showWelcome ? (
        <WelcomeScreen onGetStarted={() => setShowWelcome(false)} />
      ) : (
        <MainTabs />
      )}
    </SafeAreaView>
  );
}