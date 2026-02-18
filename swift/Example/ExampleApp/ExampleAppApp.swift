//
//  ExampleAppApp.swift
//  ExampleApp
//
//  Created by 6119501 on 16/02/26.
//

import SwiftUI

@main
struct ExampleAppApp: App {
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedWelcome {
                MainTabView()
            } else {
                WelcomeView(hasCompletedWelcome: $hasCompletedWelcome)
            }
        }
    }
}