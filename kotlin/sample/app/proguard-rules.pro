# Edge Veda Example App ProGuard Rules

# Keep Edge Veda SDK classes
-keep class com.edgeveda.sdk.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Compose
-dontwarn androidx.compose.**

# CameraX
-keep class androidx.camera.** { *; }