import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { AppTheme } from './theme';
import { ChatScreen } from './ChatScreen';
import { VisionScreen } from './VisionScreen';
import { STTScreen } from './STTScreen';
import { ImageGenerationScreen } from './ImageGenerationScreen';
import { SettingsScreen } from './SettingsScreen';
import { DetectiveScreen } from './DetectiveScreen';
import { SoakTestScreen } from './SoakTestScreen';

type TabKey = 'chat' | 'vision' | 'stt' | 'image' | 'settings';
type OverlayScreen = 'detective' | 'soaktest' | null;

interface Tab {
  key: TabKey;
  label: string;
  icon: string;
}

const TABS: Tab[] = [
  { key: 'chat', label: 'Chat', icon: '💬' },
  { key: 'vision', label: 'Vision', icon: '📷' },
  { key: 'stt', label: 'Speech', icon: '🎙️' },
  { key: 'image', label: 'Image', icon: '🎨' },
  { key: 'settings', label: 'Settings', icon: '⚙️' },
];

/**
 * Bottom tab navigation matching Flutter's MainTabs.
 *
 * Tabs: Chat, Vision, Speech (STT), Image Gen, Settings
 * Settings can deep-link to Detective and Soak Test overlay screens.
 */
export function MainTabs(): React.JSX.Element {
  const [activeTab, setActiveTab] = useState<TabKey>('chat');
  const [overlay, setOverlay] = useState<OverlayScreen>(null);

  // If an overlay screen is active, render it fullscreen (no tab bar)
  if (overlay === 'detective') {
    return (
      <View style={styles.container}>
        <View style={styles.overlayBack}>
          <TouchableOpacity onPress={() => setOverlay(null)} style={styles.backButton}>
            <Text style={styles.backButtonText}>← Settings</Text>
          </TouchableOpacity>
        </View>
        <View style={styles.overlayContent}>
          <DetectiveScreen />
        </View>
      </View>
    );
  }

  if (overlay === 'soaktest') {
    return (
      <View style={styles.container}>
        <View style={styles.overlayBack}>
          <TouchableOpacity onPress={() => setOverlay(null)} style={styles.backButton}>
            <Text style={styles.backButtonText}>← Settings</Text>
          </TouchableOpacity>
        </View>
        <View style={styles.overlayContent}>
          <SoakTestScreen />
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.content}>
        {activeTab === 'chat' && <ChatScreen />}
        {activeTab === 'vision' && <VisionScreen />}
        {activeTab === 'stt' && <STTScreen />}
        {activeTab === 'image' && <ImageGenerationScreen />}
        {activeTab === 'settings' && (
          <SettingsScreen onNavigate={(screen) => setOverlay(screen)} />
        )}
      </View>

      <View style={styles.tabBar}>
        {TABS.map((tab) => {
          const isActive = activeTab === tab.key;
          return (
            <TouchableOpacity
              key={tab.key}
              style={styles.tab}
              onPress={() => setActiveTab(tab.key)}
              activeOpacity={0.7}
            >
              <Text style={[styles.tabIcon, isActive && styles.tabIconActive]}>
                {tab.icon}
              </Text>
              <Text style={[styles.tabLabel, isActive && styles.tabLabelActive]}>
                {tab.label}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: AppTheme.background,
  },
  content: {
    flex: 1,
  },
  tabBar: {
    flexDirection: 'row',
    backgroundColor: AppTheme.background,
    borderTopWidth: 1,
    borderTopColor: AppTheme.border,
    paddingBottom: 4,
  },
  tab: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 8,
  },
  tabIcon: {
    fontSize: 18,
    opacity: 0.5,
  },
  tabIconActive: {
    opacity: 1,
  },
  tabLabel: {
    fontSize: 10,
    color: AppTheme.textSecondary,
    marginTop: 2,
  },
  tabLabelActive: {
    color: AppTheme.accent,
  },

  // Overlay navigation
  overlayBack: {
    backgroundColor: AppTheme.background,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: AppTheme.border,
  },
  backButton: { paddingVertical: 4 },
  backButtonText: { fontSize: 14, color: AppTheme.accent, fontWeight: '600' },
  overlayContent: { flex: 1 },
});
