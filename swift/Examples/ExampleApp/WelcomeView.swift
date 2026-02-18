import SwiftUI

/// Premium onboarding/welcome screen with bold red "V" branding.
///
/// Matches the Flutter WelcomeScreen pixel-for-pixel:
/// - Radial red glow behind the "V" logo
/// - Bold red "V" (Netflix-style) on true black background
/// - "Veda" title with subtle letter spacing
/// - "On-Device Intelligence" subtitle
/// - Teal "Get Started" pill button
/// - "100% Private" tagline
@available(iOS 15.0, *)
struct WelcomeView: View {
    let onGetStarted: () -> Void

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Bold red "V" with radial glow
                ZStack {
                    // Radial red glow behind logo
                    RadialGradient(
                        gradient: Gradient(colors: [
                            AppTheme.brandRed.opacity(0.15),
                            Color.clear,
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                    .frame(width: 200, height: 200)

                    // Thick "V" drawn as polygon
                    ThickVShape()
                        .fill(AppTheme.brandRed)
                        .frame(width: 140, height: 140)
                }
                .frame(width: 200, height: 200)

                Spacer().frame(height: 32)

                // App name
                Text("Veda")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .tracking(4)

                Spacer().frame(height: 8)

                // Subtitle
                Text("On-Device Intelligence")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary)

                Spacer().frame(height: 48)

                // "Get Started" button — teal pill
                Button(action: onGetStarted) {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.background)
                        .frame(maxWidth: 280, minHeight: 56)
                        .background(AppTheme.accent)
                        .clipShape(Capsule())
                }

                Spacer().frame(height: 24)

                // Privacy tagline
                Text("100% Private. Runs entirely on your device.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
        }
    }
}

/// Draws a thick "V" as a filled polygon matching the app icon style.
struct ThickVShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: w * 0.166, y: h * 0.146))    // top-left outer
        path.addLine(to: CGPoint(x: w * 0.322, y: h * 0.146))  // top-left inner
        path.addLine(to: CGPoint(x: w * 0.500, y: h * 0.703))  // inner bottom
        path.addLine(to: CGPoint(x: w * 0.678, y: h * 0.146))  // top-right inner
        path.addLine(to: CGPoint(x: w * 0.834, y: h * 0.146))  // top-right outer
        path.addLine(to: CGPoint(x: w * 0.500, y: h * 0.850))  // outer bottom
        path.closeSubpath()

        return path
    }
}