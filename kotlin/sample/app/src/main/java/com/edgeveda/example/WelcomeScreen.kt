package com.edgeveda.example

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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
@Composable
fun WelcomeScreen(onGetStarted: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppTheme.background),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Bold red "V" with radial glow
            Box(
                modifier = Modifier.size(200.dp),
                contentAlignment = Alignment.Center,
            ) {
                // Radial red glow behind logo
                Canvas(modifier = Modifier.size(200.dp)) {
                    drawCircle(
                        brush = Brush.radialGradient(
                            colors = listOf(
                                AppTheme.brandRed.copy(alpha = 0.15f),
                                AppTheme.brandRed.copy(alpha = 0f),
                            ),
                            center = Offset(size.width / 2, size.height / 2),
                            radius = size.width * 0.6f,
                        ),
                    )
                }

                // Thick "V" drawn as polygon
                Canvas(modifier = Modifier.size(140.dp)) {
                    val w = size.width
                    val h = size.height
                    val path = Path().apply {
                        moveTo(w * 0.166f, h * 0.146f)
                        lineTo(w * 0.322f, h * 0.146f)
                        lineTo(w * 0.500f, h * 0.703f)
                        lineTo(w * 0.678f, h * 0.146f)
                        lineTo(w * 0.834f, h * 0.146f)
                        lineTo(w * 0.500f, h * 0.850f)
                        close()
                    }
                    drawPath(path, color = AppTheme.brandRed, style = Fill)
                }
            }

            Spacer(modifier = Modifier.height(32.dp))

            // App name
            Text(
                text = "Veda",
                fontSize = 36.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.textPrimary,
                letterSpacing = 4.sp,
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Subtitle
            Text(
                text = "On-Device Intelligence",
                fontSize = 16.sp,
                color = AppTheme.textSecondary,
            )

            Spacer(modifier = Modifier.height(48.dp))

            // "Get Started" button — teal pill
            Button(
                onClick = onGetStarted,
                modifier = Modifier
                    .widthIn(max = 280.dp)
                    .fillMaxWidth()
                    .height(56.dp),
                shape = RoundedCornerShape(28.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = AppTheme.accent,
                    contentColor = AppTheme.background,
                ),
            ) {
                Text(
                    text = "Get Started",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Privacy tagline
            Text(
                text = "100% Private. Runs entirely on your device.",
                fontSize = 12.sp,
                color = AppTheme.textTertiary,
                textAlign = TextAlign.Center,
            )
        }
    }
}