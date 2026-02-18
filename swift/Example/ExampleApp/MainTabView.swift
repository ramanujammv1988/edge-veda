//
//  MainTabView.swift
//  ExampleApp
//
//  4-tab navigation matching Flutter app
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Content area
                TabView(selection: $selectedTab) {
                    ChatView()
                        .tag(0)
                    
                    VisionView()
                        .tag(1)
                    
                    STTView()
                        .tag(2)
                    
                    SettingsView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Custom bottom navigation
                HStack(spacing: 0) {
                    TabButton(
                        icon: "message.fill",
                        title: "Chat",
                        isSelected: selectedTab == 0
                    ) {
                        selectedTab = 0
                    }
                    
                    TabButton(
                        icon: "camera.fill",
                        title: "Vision",
                        isSelected: selectedTab == 1
                    ) {
                        selectedTab = 1
                    }
                    
                    TabButton(
                        icon: "mic.fill",
                        title: "STT",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }
                    
                    TabButton(
                        icon: "gearshape.fill",
                        title: "Settings",
                        isSelected: selectedTab == 3
                    ) {
                        selectedTab = 3
                    }
                }
                .frame(height: 80)
                .background(AppTheme.surface)
            }
        }
    }
}

// MARK: - Tab Button
struct TabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                
                Text(title)
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                
                // Selection indicator
                Circle()
                    .fill(isSelected ? AppTheme.navPill : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
}