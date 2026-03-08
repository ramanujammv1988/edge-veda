package com.edgeveda.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Camera
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Edge Veda Example App — Jetpack Compose
 *
 * A full demonstration app showcasing the Edge Veda SDK for on-device
 * LLM inference on Android. Mirrors the Flutter example app's UI.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            VedaExampleApp()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VedaExampleApp() {
    var showWelcome by remember { mutableStateOf(true) }

    MaterialTheme(
        colorScheme = darkColorScheme(
            background = AppTheme.background,
            surface = AppTheme.surface,
            primary = AppTheme.accent,
            secondary = AppTheme.accentDim,
            onSurface = AppTheme.textPrimary,
            onPrimary = AppTheme.background,
            error = AppTheme.danger,
        )
    ) {
        if (showWelcome) {
            WelcomeScreen(onGetStarted = { showWelcome = false })
        } else {
            MainScreen()
        }
    }
}

data class TabItem(
    val title: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
)

@Composable
fun MainScreen() {
    var selectedTab by remember { mutableIntStateOf(0) }

    val tabs = listOf(
        TabItem("Chat", Icons.Filled.ChatBubble, Icons.Outlined.ChatBubbleOutline),
        TabItem("Vision", Icons.Filled.Camera, Icons.Outlined.CameraAlt),
        TabItem("Listen", Icons.Filled.Mic, Icons.Outlined.MicNone),
        TabItem("Benchmark", Icons.Filled.Speed, Icons.Outlined.Speed),
        TabItem("Settings", Icons.Filled.Settings, Icons.Outlined.Settings),
    )

    Scaffold(
        containerColor = AppTheme.background,
        bottomBar = {
            NavigationBar(
                containerColor = AppTheme.background,
                contentColor = AppTheme.textSecondary,
            ) {
                tabs.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        icon = {
                            Icon(
                                imageVector = if (selectedTab == index) tab.selectedIcon else tab.unselectedIcon,
                                contentDescription = tab.title,
                            )
                        },
                        label = { Text(tab.title) },
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = AppTheme.accent,
                            selectedTextColor = AppTheme.accent,
                            unselectedIconColor = AppTheme.textSecondary,
                            unselectedTextColor = AppTheme.textSecondary,
                            indicatorColor = AppTheme.accent.copy(alpha = 0.15f),
                        ),
                    )
                }
            }
        }
    ) { padding ->
        when (selectedTab) {
            0 -> ChatScreen(modifier = Modifier.padding(padding))
            1 -> VisionScreen(modifier = Modifier.padding(padding))
            2 -> SttScreen(modifier = Modifier.padding(padding))
            3 -> SoakTestScreen(modifier = Modifier.padding(padding))
            4 -> SettingsScreen(modifier = Modifier.padding(padding))
        }
    }
}