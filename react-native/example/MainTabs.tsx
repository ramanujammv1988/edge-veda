import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { AppTheme } from './theme';
import { ChatScreen } from './ChatScreen';
import { VisionScreen } from './VisionScreen';
import { SettingsScreen } from './SettingsScreen';

type TabKey = 'chat' | 'vision' | 'settings';

interface Tab {
  key: TabKey;
  label: string;
  icon: string;
}

const TABS: Tab[] = [
  { key: 'chat', label: 'Chat', icon: '💬' },
  { key: 'vision', label: 'Vision', icon: '📷' },
  { key: 'settings', label: 'Settings', icon: '⚙️' },
];

/**
 * Bottom tab navigation matching Flutter's MainTabs.
 */
export function MainTabs(): React.JSX.Element {
  const [activeTab, setActiveTab] = useState<TabKey>('chat');

  return (
    <View style={styles.container}>
      <View style={styles.content}>
        {activeTab === 'chat' && <ChatScreen />}
        {activeTab === 'vision' && <VisionScreen />}
        {activeTab === 'settings' && <SettingsScreen />}
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
    fontSize: 20,
    opacity: 0.5,
  },
  tabIconActive: {
    opacity: 1,
  },
  tabLabel: {
    fontSize: 11,
    color: AppTheme.textSecondary,
    marginTop: 2,
  },
  tabLabelActive: {
    color: AppTheme.accent,
  },
});