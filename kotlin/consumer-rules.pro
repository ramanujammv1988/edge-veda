# Consumer ProGuard rules for EdgeVeda SDK
# These rules are applied to apps that use this library

# Keep all public API
-keep public class com.edgeveda.sdk.EdgeVeda { public *; }
-keep public class com.edgeveda.sdk.EdgeVedaConfig { public *; }
-keep public class com.edgeveda.sdk.GenerateOptions { public *; }
-keep public enum com.edgeveda.sdk.Backend { *; }

# Keep native methods
-keepclasseswithmembernames class com.edgeveda.sdk.internal.NativeBridge {
    native <methods>;
}
