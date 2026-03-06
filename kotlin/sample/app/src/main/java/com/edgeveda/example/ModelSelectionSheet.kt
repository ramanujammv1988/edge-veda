package com.edgeveda.example

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
 * Model selection bottom sheet matching Flutter's ModelSelectionSheet.
 *
 * Shows device status header, available models with download/select actions.
 */
@Composable
fun ModelSelectionSheet() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val modelManager = remember { ModelManager(context) }

    val models = listOf(
        ModelRegistry.llama32_1b,
        ModelRegistry.smolvlm2_500m,
        ModelRegistry.smolvlm2_500m_mmproj,
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppTheme.surface)
            .padding(bottom = 40.dp),
    ) {
        // Handle
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 16.dp),
            horizontalArrangement = Arrangement.Center,
        ) {
            Box(
                modifier = Modifier
                    .width(40.dp)
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(AppTheme.textTertiary),
            )
        }

        // Title
        Text(
            "Models",
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.textPrimary,
            modifier = Modifier.padding(horizontal = 20.dp),
        )

        Spacer(Modifier.height(16.dp))

        // Device status card
        Row(
            modifier = Modifier
                .padding(horizontal = 16.dp)
                .fillMaxWidth()
                .background(AppTheme.surfaceVariant, RoundedCornerShape(12.dp))
                .border(1.dp, AppTheme.border, RoundedCornerShape(12.dp))
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(AppTheme.accent.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.PhoneAndroid, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column {
                Text(Build.MODEL, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AppTheme.textPrimary)
                Spacer(Modifier.height(2.dp))
                Text(
                    "${Runtime.getRuntime().maxMemory() / (1024 * 1024)} MB RAM • ${Build.HARDWARE}",
                    fontSize = 12.sp,
                    color = AppTheme.textSecondary,
                )
            }
        }

        Spacer(Modifier.height(20.dp))

        Text(
            "AVAILABLE MODELS",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppTheme.textTertiary,
            letterSpacing = 1.sp,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        )

        // Model cards
        models.forEach { model ->
            SheetModelCard(model, modelManager)
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun SheetModelCard(model: DownloadableModelInfo, modelManager: ModelManager) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isDownloaded by remember { mutableStateOf<Boolean?>(null) }
    var isDownloading by remember { mutableStateOf(false) }
    var downloadProgress by remember { mutableDoubleStateOf(0.0) }

    LaunchedEffect(model.id) {
        isDownloaded = modelManager.isModelDownloaded(model.id)
    }

    val icon = when {
        model.id.contains("mmproj") -> Icons.Outlined.Extension
        model.id.contains("vlm") || model.id.contains("smol") -> Icons.Outlined.Visibility
        else -> Icons.Outlined.SmartToy
    }

    val sizeMb = model.sizeBytes / (1024.0 * 1024)
    val sizeLabel = if (sizeMb >= 1024) "${String.format("%.1f", sizeMb / 1024)} GB" else "${sizeMb.toInt()} MB"

    Row(
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .background(AppTheme.surface, RoundedCornerShape(12.dp))
            .border(1.dp, AppTheme.border, RoundedCornerShape(12.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Model icon
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(AppTheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(24.dp))
        }
        Spacer(Modifier.width(12.dp))

        // Name + meta
        Column(modifier = Modifier.weight(1f)) {
            Text(model.name, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AppTheme.textPrimary)
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(sizeLabel, fontSize = 12.sp, color = AppTheme.textSecondary)
                Text("•", fontSize = 12.sp, color = AppTheme.textTertiary)
                Text(model.quantization ?: "", fontSize = 12.sp, color = AppTheme.textSecondary)
            }
        }

        // Status / Action
        if (isDownloading) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(
                    progress = downloadProgress.toFloat(),
                    modifier = Modifier.size(32.dp),
                    strokeWidth = 3.dp,
                    color = AppTheme.accent,
                    trackColor = AppTheme.surfaceVariant,
                )
                Spacer(Modifier.height(4.dp))
                Text("${(downloadProgress * 100).toInt()}%", fontSize = 10.sp, color = AppTheme.textSecondary)
            }
        } else when (isDownloaded) {
            true -> {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(AppTheme.success.copy(alpha = 0.15f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = AppTheme.success, modifier = Modifier.size(20.dp))
                }
            }
            false -> {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(AppTheme.accent.copy(alpha = 0.15f))
                        .clickable {
                            isDownloading = true
                            scope.launch {
                                try {
                    modelManager.downloadModel(model, onProgress = { progress ->
                        downloadProgress = progress.progress
                    })
                                    isDownloaded = true
                                } catch (_: Exception) { }
                                isDownloading = false
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Outlined.CloudDownload, contentDescription = "Download", tint = AppTheme.accent, modifier = Modifier.size(20.dp))
                }
            }
            null -> {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp, color = AppTheme.accent)
            }
        }
    }
}