import SwiftUI
import EdgeVeda

/// Edge Veda Example App — SwiftUI
///
/// A full demonstration app showcasing the Edge Veda SDK for on-device
/// LLM inference. Mirrors the Flutter example app's UI and functionality.
@main
@available(iOS 16.0, *)
struct VedaExampleApp: App {
    @State private var showWelcome = true

    var body: some Scene {
        WindowGroup {
            if showWelcome {
                WelcomeView(onGetStarted: { showWelcome = false })
            } else {
                MainTabView()
            }
        }
    }
}

/// Main tab navigation matching Flutter's bottom NavigationBar
@available(iOS 16.0, *)
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "bubble.left.fill" : "bubble.left")
                    Text("Chat")
                }
                .tag(0)

            VisionView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "camera.fill" : "camera")
                    Text("Vision")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "gearshape.fill" : "gearshape")
                    Text("Settings")
                }
                .tag(2)
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }
}