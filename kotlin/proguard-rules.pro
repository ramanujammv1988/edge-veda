# EdgeVeda SDK ProGuard Rules

# Keep all public API classes and methods
-keep public class com.edgeveda.sdk.** { public *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep custom exceptions
-keep public class * extends com.edgeveda.sdk.EdgeVedaException

# Keep data classes (used for serialization/deserialization)
-keep class com.edgeveda.sdk.EdgeVedaConfig { *; }
-keep class com.edgeveda.sdk.GenerateOptions { *; }
-keep class com.edgeveda.sdk.ModelInfo { *; }
-keep class com.edgeveda.sdk.DeviceInfo { *; }
-keep class com.edgeveda.sdk.GenerationStats { *; }

# Keep enums
-keepclassmembers enum com.edgeveda.sdk.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep callback interfaces
-keep interface com.edgeveda.sdk.StreamCallback { *; }
-keep interface com.edgeveda.sdk.internal.StreamCallbackBridge { *; }

# Preserve line numbers for debugging
-keepattributes SourceFile,LineNumberTable

# Preserve annotations
-keepattributes *Annotation*

# Keep generic signatures
-keepattributes Signature

# Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# Kotlin metadata
-keep class kotlin.Metadata { *; }
