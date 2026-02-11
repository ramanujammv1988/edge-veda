package com.edgeveda

import com.facebook.react.TurboReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.turbomodule.core.interfaces.TurboModule

/**
 * Edge Veda React Package
 * Dual architecture support - automatically registers the correct module variant
 */
class EdgeVedaPackage : TurboReactPackage() {

    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return if (name == "EdgeVeda") {
            EdgeVedaModule(reactContext)
        } else {
            null
        }
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider {
            val isTurboModule = BuildConfig.IS_NEW_ARCHITECTURE_ENABLED
            
            mapOf(
                "EdgeVeda" to ReactModuleInfo(
                    "EdgeVeda",
                    "com.edgeveda.EdgeVedaModule",
                    false, // canOverrideExistingModule
                    false, // needsEagerInit
                    true,  // hasConstants
                    false, // isCxxModule
                    isTurboModule // isTurboModule - set based on architecture
                )
            )
        }
    }
}
