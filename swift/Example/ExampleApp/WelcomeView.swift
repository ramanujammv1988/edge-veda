//
//  WelcomeView.swift
//  ExampleApp
//
//  Premium onboarding screen with red "V" branding
//

import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo with glow
                ZStack {
                    // Radial glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    AppTheme.brandRed.opacity(0.15),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                    
                    // "V" logo
                    VLogoShape()
                        .fill(AppTheme.brandRed)
                        .frame(width: 140, height: 140)
                }
                .frame(width: 200, height: 200)
                
                Spacer()
                    .frame(height: 48)
                
                // App name
                Text("Veda")
                    .font(AppTheme.Typography.headlineLarge)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.textPrimary)
                    .kerning(4)
                
                Spacer()
                    .frame(height: 16)
                
                // Subtitle
                Text("On-Device Intelligence")
                    .font(AppTheme.Typography.bodyLarge)
                    .foregroundColor(AppTheme.textSecondary)
                
                Spacer()
                
                // Get Started button
                Button(action: onGetStarted) {
                    Text("Get Started")
                        .font(AppTheme.Typography.bodyLarge)
                        .fontWeight(.semibold)
                        .frame(maxWidth: 280)
                }
                .appButton()
                .frame(height: 56)
                
                Spacer()
                    .frame(height: 32)
                
                // Privacy tagline
                Text("100% Private. Runs entirely on your device.")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                    .frame(height: 48)
            }
            .padding(.horizontal, AppTheme.Layout.padding)
        }
    }
}

// MARK: - V Logo Shape
struct VLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Scale factor from 1024x1024 design to actual rect
        let scaleX = rect.width / 1024
        let scaleY = rect.height / 1024
        
        // V polygon points (matching Flutter _ThickVPainter)
        let points: [(CGFloat, CGFloat)] = [
            (320, 200),   // Top left outer
            (512, 680),   // Bottom center
            (704, 200),   // Top right outer
            (600, 200),   // Top right inner
            (512, 520),   // Bottom center inner
            (424, 200)    // Top left inner
        ]
        
        // Scale and draw polygon
        let scaledPoints = points.map { point in
            CGPoint(
                x: rect.minX + point.0 * scaleX,
                y: rect.minY + point.1 * scaleY
            )
        }
        
        if let firstPoint = scaledPoints.first {
            path.move(to: firstPoint)
            for point in scaledPoints.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        
        return path
    }
}

#Preview {
    WelcomeView(onGetStarted: {})
}