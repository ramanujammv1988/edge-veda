package com.edgeveda.example

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.edgeveda.sdk.*
import kotlinx.coroutines.launch

/**
 * Settings screen matching Flutter's SettingsScreen.
 *
 * Sections: Device Status, Capability Tier + Recommended Models,
 * Generation (sliders), Storage, Models, About.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var temperature by remember { mutableFloatStateOf(0.7f) }
    var maxTokens by remember { mutableFloatStateOf(256f) }

    // Detect device capabilities once on composition
    val deviceProfile = remember { detectDeviceCapabilities(context) }

    // All models across every category
    val allModels = remember {
        ModelRegistry.getAllTextModels() +
        ModelRegistry.getVisionModels() +
        listOf(ModelRegistry.smolvlm2_500m_mmproj) +
        ModelRegistry.getWhisperModels() +
        ModelRegistry.getEmbeddingModels()
    }

    // Recommended models (text + whisper only; no vision/mmproj/embedding bloat in recommender)
    val recommendedModels = remember {
        recommendModels(
            deviceProfile,
            ModelRegistry.getAllTextModels() + ModelRegistry.getWhisperModels()
        ).take(3)
    }

    Column(modifier = modifier.fillMaxSize().background(AppTheme.background)) {
        CenterAlignedTopAppBar(
            title = { Text("Settings", color = AppTheme.textPrimary) },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppTheme.background),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // ─── Device Status ───────────────────────────────────────────────
            SettingsSection("Device Status") {
                SettingsCard {
                    AboutRow(Icons.Outlined.PhoneAndroid, "Model", Build.MODEL)
                    SettingsDivider()
                    AboutRow(Icons.Outlined.DeveloperBoard, "Chip", Build.HARDWARE)
                    SettingsDivider()
                    AboutRow(
                        Icons.Outlined.Memory,
                        "Total RAM",
                        "${deviceProfile.totalMemoryMb} MB",
                    )
                    SettingsDivider()
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.Psychology, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.width(12.dp))
                        Text("NNAPI", fontSize = 14.sp, color = AppTheme.textPrimary)
                        Spacer(Modifier.weight(1f))
                        Icon(
                            if (Build.VERSION.SDK_INT >= 27) Icons.Outlined.CheckCircle else Icons.Outlined.Cancel,
                            contentDescription = null,
                            tint = if (Build.VERSION.SDK_INT >= 27) AppTheme.success else AppTheme.textTertiary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    SettingsDivider()
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.Layers, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.width(12.dp))
                        Text("Vulkan", fontSize = 14.sp, color = AppTheme.textPrimary)
                        Spacer(Modifier.weight(1f))
                        Icon(
                            if (deviceProfile.hasVulkan) Icons.Outlined.CheckCircle else Icons.Outlined.Cancel,
                            contentDescription = null,
                            tint = if (deviceProfile.hasVulkan) AppTheme.success else AppTheme.textTertiary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }

            // ─── Capability Tier + Recommended Models ────────────────────────
            SettingsSection("Device Capability") {
                SettingsCard {
                    val tier = when {
                        deviceProfile.totalMemoryMb < 4096  -> "Low"
                        deviceProfile.totalMemoryMb < 6144  -> "Medium"
                        deviceProfile.totalMemoryMb < 8192  -> "High"
                        else                                 -> "Ultra"
                    }
                    val tierColor = when (tier) {
                        "Ultra"  -> AppTheme.accent
                        "High"   -> AppTheme.success
                        "Medium" -> AppTheme.warning
                        else     -> AppTheme.textTertiary
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.Speed, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.width(12.dp))
                        Text("Tier", fontSize = 14.sp, color = AppTheme.textPrimary)
                        Spacer(Modifier.weight(1f))
                        Surface(
                            shape = RoundedCornerShape(20.dp),
                            color = tierColor.copy(alpha = 0.15f),
                        ) {
                            Text(
                                tier,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = tierColor,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                            )
                        }
                    }

                    if (recommendedModels.isNotEmpty()) {
                        SettingsDivider()
                        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                            Text(
                                "Recommended for this device",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Medium,
                                color = AppTheme.textTertiary,
                            )
                            Spacer(Modifier.height(8.dp))
                            recommendedModels.forEach { model ->
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(
                                        modelIcon(model),
                                        contentDescription = null,
                                        tint = AppTheme.accent,
                                        modifier = Modifier.size(16.dp),
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(model.name, fontSize = 13.sp, color = AppTheme.textPrimary, modifier = Modifier.weight(1f))
                                    Text(modelSizeLabel(model), fontSize = 12.sp, color = AppTheme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }

            // ─── Generation ──────────────────────────────────────────────────
            SettingsSection("Generation") {
                SettingsCard {
                    SettingRow(Icons.Outlined.Thermostat, "Temperature", String.format("%.1f", temperature))
                    Slider(
                        value = temperature, onValueChange = { temperature = it },
                        valueRange = 0f..2f, steps = 19,
                        colors = SliderDefaults.colors(thumbColor = AppTheme.accent, activeTrackColor = AppTheme.accent, inactiveTrackColor = AppTheme.border),
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Precise", fontSize = 11.sp, color = AppTheme.textTertiary)
                        Text("Creative", fontSize = 11.sp, color = AppTheme.textTertiary)
                    }
                    SettingsDivider()
                    SettingRow(Icons.Outlined.Article, "Max Tokens", "${maxTokens.toInt()}")
                    Slider(
                        value = maxTokens, onValueChange = { maxTokens = it },
                        valueRange = 32f..1024f, steps = 30,
                        colors = SliderDefaults.colors(thumbColor = AppTheme.accent, activeTrackColor = AppTheme.accent, inactiveTrackColor = AppTheme.border),
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Short", fontSize = 11.sp, color = AppTheme.textTertiary)
                        Text("Long", fontSize = 11.sp, color = AppTheme.textTertiary)
                    }
                }
            }

            // ─── Storage ─────────────────────────────────────────────────────
            SettingsSection("Storage") {
                val totalBytes = allModels.sumOf { it.sizeBytes }
                val totalGb = totalBytes / (1024.0 * 1024 * 1024)

                SettingsCard {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.Storage, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
                            Spacer(Modifier.width(12.dp))
                            Text("All Models", fontSize = 14.sp, color = AppTheme.textPrimary)
                            Spacer(Modifier.weight(1f))
                            Text("~${String.format("%.1f", totalGb)} GB", fontSize = 14.sp, color = AppTheme.textSecondary)
                        }
                        Spacer(Modifier.height(12.dp))
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .clip(RoundedCornerShape(3.dp))
                                .background(AppTheme.surfaceVariant),
                        ) {
                            Box(
                                modifier = Modifier
                                    .fillMaxHeight()
                                    .fillMaxWidth((totalGb / 8.0).coerceIn(0.0, 1.0).toFloat())
                                    .clip(RoundedCornerShape(3.dp))
                                    .background(AppTheme.accent),
                            )
                        }
                        Spacer(Modifier.height(8.dp))
                        Text("${String.format("%.1f", totalGb)} GB if all downloaded (of 8 GB scale)", fontSize = 11.sp, color = AppTheme.textTertiary)
                    }
                }
            }

            // ─── Models ──────────────────────────────────────────────────────
            SettingsSection("Models") {
                SettingsCard {
                    allModels.forEachIndexed { index, model ->
                        ModelRowItem(model)
                        if (index < allModels.lastIndex) SettingsDivider()
                    }
                }
            }

            // ─── About ───────────────────────────────────────────────────────
            SettingsSection("About") {
                SettingsCard {
                    AboutRow(Icons.Outlined.AutoAwesome, "Veda", BuildConfig.VERSION_NAME)
                    SettingsDivider()
                    AboutRow(Icons.Outlined.Code, "Veda SDK", BuildConfig.VERSION_NAME)
                    SettingsDivider()
                    AboutRow(Icons.Outlined.Memory, "Backend", "CPU")
                    SettingsDivider()
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Icon(Icons.Outlined.Shield, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("Privacy", fontSize = 14.sp, color = AppTheme.textPrimary)
                            Spacer(Modifier.height(2.dp))
                            Text("All inference runs locally on device", fontSize = 12.sp, color = AppTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

// ─── Helper functions ────────────────────────────────────────────────────────

private fun modelIcon(model: DownloadableModelInfo) = when (model.modelType) {
    ModelType.WHISPER    -> Icons.Outlined.Mic
    ModelType.EMBEDDING  -> Icons.Outlined.Analytics
    ModelType.VISION     -> Icons.Outlined.Visibility
    ModelType.MMPROJ     -> Icons.Outlined.Extension
    else                 -> Icons.Outlined.SmartToy
}

private fun modelSizeLabel(model: DownloadableModelInfo): String {
    val sizeMb = model.sizeBytes / (1024.0 * 1024)
    return if (sizeMb >= 1024) "~${String.format("%.1f", sizeMb / 1024)} GB"
    else "~${sizeMb.toInt()} MB"
}

// ─── Layout primitives ───────────────────────────────────────────────────────

@Composable
private fun SettingsSection(title: String, content: @Composable () -> Unit) {
    Column {
        Text(
            title.uppercase(),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppTheme.accent,
            letterSpacing = 1.2.sp,
            modifier = Modifier.padding(start = 20.dp, bottom = 8.dp),
        )
        content()
    }
}

@Composable
private fun SettingsCard(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .background(AppTheme.surface, RoundedCornerShape(16.dp))
            .border(1.dp, AppTheme.border, RoundedCornerShape(16.dp)),
        content = content,
    )
}

@Composable
private fun SettingsDivider() {
    HorizontalDivider(color = AppTheme.border, modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
private fun SettingRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(title, fontSize = 14.sp, color = AppTheme.textPrimary)
        Spacer(Modifier.weight(1f))
        Text(value, fontSize = 14.sp, color = AppTheme.accent)
    }
}

@Composable
private fun AboutRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(title, fontSize = 14.sp, color = AppTheme.textPrimary)
        Spacer(Modifier.weight(1f))
        Text(value, fontSize = 14.sp, color = AppTheme.textSecondary)
    }
}

@Composable
private fun ModelRowItem(model: DownloadableModelInfo) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isDownloaded by remember { mutableStateOf<Boolean?>(null) }
    var isDeleting by remember { mutableStateOf(false) }

    LaunchedEffect(model.id) {
        isDownloaded = ModelManager(context).isModelDownloaded(model.id)
    }

    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(modelIcon(model), contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(model.name, fontSize = 14.sp, color = AppTheme.textPrimary)
            Spacer(Modifier.height(2.dp))
            Text(modelSizeLabel(model), fontSize = 12.sp, color = AppTheme.textSecondary)
        }

        if (isDeleting) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = AppTheme.accent)
        } else when (isDownloaded) {
            true -> {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = AppTheme.success, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Icon(
                    Icons.Outlined.Delete, contentDescription = "Delete",
                    tint = AppTheme.textTertiary,
                    modifier = Modifier.size(20.dp).clickable {
                        isDeleting = true
                        scope.launch {
                            ModelManager(context).deleteModel(model.id)
                            isDownloaded = false
                            isDeleting = false
                        }
                    },
                )
            }
            false -> Icon(Icons.Outlined.CloudDownload, contentDescription = null, tint = AppTheme.textTertiary, modifier = Modifier.size(20.dp))
            null -> CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = AppTheme.accent)
        }
    }
}
