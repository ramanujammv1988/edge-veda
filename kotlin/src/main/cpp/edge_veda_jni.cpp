#include <jni.h>
#include <android/log.h>
#include <string>
#include <memory>
#include <vector>
#include <mutex>
#include <cstring>
#include <map>

// Include Edge Veda C API
#include "../../../../core/include/edge_veda.h"

#define LOG_TAG "EdgeVedaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

namespace {

/**
 * Memory pressure callback data
 */
struct MemoryCallbackData {
    JavaVM* jvm;
    jobject callback; // Global reference
};

// Map to store memory callbacks per context
static std::map<ev_context, MemoryCallbackData> memory_callbacks;
static std::mutex callback_mutex;

/**
 * C callback trampoline for memory pressure events
 */
void memory_pressure_callback_trampoline(void* user_data, size_t current_bytes, size_t limit_bytes) {
    auto* ctx = static_cast<ev_context>(user_data);
    
    std::lock_guard<std::mutex> lock(callback_mutex);
    auto it = memory_callbacks.find(ctx);
    if (it == memory_callbacks.end()) {
        return;
    }
    
    MemoryCallbackData& callback_data = it->second;
    JNIEnv* env = nullptr;
    
    // Attach current thread to JVM
    jint result = callback_data.jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    bool detach_thread = false;
    
    if (result == JNI_EDETACHED) {
        result = callback_data.jvm->AttachCurrentThread(&env, nullptr);
        if (result != JNI_OK) {
            LOGE("Failed to attach thread to JVM");
            return;
        }
        detach_thread = true;
    }
    
    // Call Java callback
    jclass callback_class = env->GetObjectClass(callback_data.callback);
    jmethodID method = env->GetMethodID(callback_class, "onMemoryPressure", "(JJ)V");
    
    if (method) {
        env->CallVoidMethod(callback_data.callback, method, 
                          static_cast<jlong>(current_bytes), 
                          static_cast<jlong>(limit_bytes));
        
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
    }
    
    env->DeleteLocalRef(callback_class);
    
    // Detach thread if we attached it
    if (detach_thread) {
        callback_data.jvm->DetachCurrentThread();
    }
}

/**
 * Native EdgeVeda instance holding the C API context.
 */
struct EdgeVedaInstance {
    ev_context context = nullptr;
    std::mutex mutex;
    bool initialized = false;
    std::string last_error;
};

/**
 * Helper to convert jstring to std::string
 */
std::string jstring_to_string(JNIEnv* env, jstring jstr) {
    if (!jstr) return "";

    const char* chars = env->GetStringUTFChars(jstr, nullptr);
    std::string result(chars);
    env->ReleaseStringUTFChars(jstr, chars);
    return result;
}

/**
 * Helper to convert std::string to jstring
 */
jstring string_to_jstring(JNIEnv* env, const std::string& str) {
    return env->NewStringUTF(str.c_str());
}

/**
 * Helper to throw a Java exception
 */
void throw_exception(JNIEnv* env, const char* exception_class, const char* message) {
    jclass cls = env->FindClass(exception_class);
    if (cls != nullptr) {
        env->ThrowNew(cls, message);
        env->DeleteLocalRef(cls);
    }
}

/**
 * Get EdgeVedaInstance from handle
 */
EdgeVedaInstance* get_instance(jlong handle) {
    return reinterpret_cast<EdgeVedaInstance*>(handle);
}

} // anonymous namespace

extern "C" {

/**
 * Create a new native instance.
 */
JNIEXPORT jlong JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeCreate(
    JNIEnv* env,
    jobject /* this */
) {
    try {
        LOGI("Creating EdgeVeda native instance");
        auto* instance = new EdgeVedaInstance();
        return reinterpret_cast<jlong>(instance);
    } catch (const std::exception& e) {
        LOGE("Failed to create native instance: %s", e.what());
        throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$NativeError", e.what());
        return 0;
    }
}

/**
 * Initialize the model.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeInitModel(
    JNIEnv* env,
    jobject /* this */,
    jlong handle,
    jstring model_path,
    jint backend,
    jint num_threads,
    jint max_tokens,
    jint context_size,
    jint batch_size,
    jboolean use_gpu,
    jboolean use_mmap,
    jboolean use_mlock,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jfloat repeat_penalty,
    jlong seed
) {
    auto* instance = get_instance(handle);
    if (!instance) {
        throw_exception(env, "java/lang/IllegalStateException", "Invalid native handle");
        return JNI_FALSE;
    }

    try {
        std::lock_guard<std::mutex> lock(instance->mutex);

        std::string path = jstring_to_string(env, model_path);
        LOGI("========== MODEL INITIALIZATION ==========");
        LOGI("Model path: %s", path.c_str());
        LOGI("Backend requested: %d (%s)", backend, ev_backend_name(static_cast<ev_backend_t>(backend)));
        LOGI("Threads: %d (0=auto)", num_threads);
        LOGI("Context: %d, Batch: %d, MaxTokens: %d", context_size, batch_size, max_tokens);
        LOGI("GPU: useGpu=%d, layers=%d", use_gpu, use_gpu ? -1 : 0);
        LOGI("Memory: mmap=%d, mlock=%d", use_mmap, use_mlock);

        // Configure Edge Veda context
        ev_config config;
        ev_config_default(&config);
        
        config.model_path = path.c_str();
        config.backend = static_cast<ev_backend_t>(backend);
        config.num_threads = num_threads > 0 ? num_threads : 0;
        config.context_size = context_size > 0 ? context_size : 2048;
        config.batch_size = batch_size > 0 ? batch_size : 512;
        config.gpu_layers = use_gpu ? -1 : 0; // -1 = all layers, 0 = none
        config.use_mmap = use_mmap;
        config.use_mlock = use_mlock;
        config.seed = static_cast<int>(seed);
        config.memory_limit_bytes = 2147483648ULL; // 2 GB safe default for mobile
        config.auto_unload_on_memory_pressure = true;
        config.reserved = nullptr;

        // Suppress unused parameter warnings – these are reserved for future use
        (void)temperature;
        (void)top_p;
        (void)top_k;
        (void)repeat_penalty;
        (void)seed;

        // Detect actual backend that will be used
        ev_backend_t detected_backend = ev_detect_backend();
        LOGI("Detected best backend: %d (%s)", detected_backend, ev_backend_name(detected_backend));
        
        // Check if requested backend is available
        bool backend_available = ev_is_backend_available(static_cast<ev_backend_t>(backend));
        LOGI("Requested backend %d available: %d", backend, backend_available);

        // Initialize context
        ev_error_t error;
        instance->context = ev_init(&config, &error);
        
        if (!instance->context) {
            const char* error_msg = ev_error_string(error);
            instance->last_error = error_msg;
            LOGE("Failed to initialize context: %s", error_msg);
            throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$ModelLoadError", error_msg);
            return JNI_FALSE;
        }

        instance->initialized = true;
        LOGI("========== MODEL INITIALIZATION SUCCESS ==========");
        LOGI("Backend in use: %s", ev_backend_name(config.backend));
        LOGI("GPU layers offloaded: %d", config.gpu_layers);
        LOGI("Threads: %d", config.num_threads);
        return JNI_TRUE;

    } catch (const std::exception& e) {
        LOGE("Model initialization failed: %s", e.what());
        instance->last_error = e.what();
        throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$ModelLoadError", e.what());
        return JNI_FALSE;
    }
}

/**
 * Generate text synchronously.
 */
JNIEXPORT jstring JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeGenerate(
    JNIEnv* env,
    jobject /* this */,
    jlong handle,
    jstring prompt,
    jint max_tokens,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jfloat repeat_penalty,
    jobjectArray stop_sequences,
    jlong seed
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->initialized || !instance->context) {
        throw_exception(env, "java/lang/IllegalStateException", "Model not initialized");
        return nullptr;
    }

    try {
        std::lock_guard<std::mutex> lock(instance->mutex);

        std::string prompt_str = jstring_to_string(env, prompt);
        LOGI("Generating text for prompt (length: %zu)", prompt_str.length());

        // Convert stop sequences to C array
        std::vector<std::string> stop_strs;
        std::vector<const char*> stop_ptrs;
        
        if (stop_sequences) {
            jsize len = env->GetArrayLength(stop_sequences);
            for (jsize i = 0; i < len; i++) {
                auto jstr = (jstring)env->GetObjectArrayElement(stop_sequences, i);
                stop_strs.push_back(jstring_to_string(env, jstr));
                env->DeleteLocalRef(jstr);
            }
            for (const auto& s : stop_strs) {
                stop_ptrs.push_back(s.c_str());
            }
        }

        // Configure generation parameters
        ev_generation_params params;
        ev_generation_params_default(&params);
        
        if (max_tokens > 0) params.max_tokens = max_tokens;
        if (temperature > 0) params.temperature = temperature;
        if (top_p > 0) params.top_p = top_p;
        if (top_k > 0) params.top_k = top_k;
        if (repeat_penalty > 0) params.repeat_penalty = repeat_penalty;
        params.frequency_penalty = 0.0f;
        params.presence_penalty = 0.0f;
        params.stop_sequences = stop_ptrs.empty() ? nullptr : stop_ptrs.data();
        params.num_stop_sequences = static_cast<int>(stop_ptrs.size());
        params.reserved = nullptr;

        // Suppress unused parameter warning – reserved for future use
        (void)seed;

        // Generate text
        char* output = nullptr;
        ev_error_t error = ev_generate(instance->context, prompt_str.c_str(), &params, &output);
        
        if (error != EV_SUCCESS || !output) {
            const char* error_msg = ev_error_string(error);
            instance->last_error = error_msg;
            LOGE("Generation failed: %s", error_msg);
            throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$GenerationError", error_msg);
            return nullptr;
        }

        std::string result(output);
        ev_free_string(output);

        LOGI("Generation complete (length: %zu)", result.length());
        return string_to_jstring(env, result);

    } catch (const std::exception& e) {
        LOGE("Generation failed: %s", e.what());
        instance->last_error = e.what();
        throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$GenerationError", e.what());
        return nullptr;
    }
}

/**
 * Generate text with streaming callback.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeGenerateStream(
    JNIEnv* env,
    jobject /* this */,
    jlong handle,
    jstring prompt,
    jint max_tokens,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jfloat repeat_penalty,
    jobjectArray stop_sequences,
    jlong seed,
    jobject callback
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->initialized || !instance->context) {
        throw_exception(env, "java/lang/IllegalStateException", "Model not initialized");
        return JNI_FALSE;
    }

    try {
        std::lock_guard<std::mutex> lock(instance->mutex);

        std::string prompt_str = jstring_to_string(env, prompt);
        LOGI("Streaming generation for prompt (length: %zu)", prompt_str.length());

        // Get callback method
        jclass callback_class = env->GetObjectClass(callback);
        jmethodID on_token_method = env->GetMethodID(
            callback_class,
            "onToken",
            "(Ljava/lang/String;)V"
        );

        if (!on_token_method) {
            LOGE("Failed to find onToken method");
            throw_exception(env, "java/lang/NoSuchMethodError", "onToken method not found");
            return JNI_FALSE;
        }

        // Convert stop sequences to C array
        std::vector<std::string> stop_strs;
        std::vector<const char*> stop_ptrs;
        
        if (stop_sequences) {
            jsize len = env->GetArrayLength(stop_sequences);
            for (jsize i = 0; i < len; i++) {
                auto jstr = (jstring)env->GetObjectArrayElement(stop_sequences, i);
                stop_strs.push_back(jstring_to_string(env, jstr));
                env->DeleteLocalRef(jstr);
            }
            for (const auto& s : stop_strs) {
                stop_ptrs.push_back(s.c_str());
            }
        }

        // Configure generation parameters
        ev_generation_params params;
        ev_generation_params_default(&params);
        
        if (max_tokens > 0) params.max_tokens = max_tokens;
        if (temperature > 0) params.temperature = temperature;
        if (top_p > 0) params.top_p = top_p;
        if (top_k > 0) params.top_k = top_k;
        if (repeat_penalty > 0) params.repeat_penalty = repeat_penalty;
        params.frequency_penalty = 0.0f;
        params.presence_penalty = 0.0f;
        params.stop_sequences = stop_ptrs.empty() ? nullptr : stop_ptrs.data();
        params.num_stop_sequences = static_cast<int>(stop_ptrs.size());
        params.reserved = nullptr;

        // Suppress unused parameter warning – reserved for future use
        (void)seed;

        // Start streaming generation
        ev_error_t error;
        ev_stream stream = ev_generate_stream(instance->context, prompt_str.c_str(), &params, &error);
        
        if (!stream) {
            const char* error_msg = ev_error_string(error);
            instance->last_error = error_msg;
            LOGE("Failed to start stream: %s", error_msg);
            throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$GenerationError", error_msg);
            return JNI_FALSE;
        }

        // Stream tokens
        while (ev_stream_has_next(stream)) {
            char* token = ev_stream_next(stream, &error);
            
            if (!token) {
                // ev_stream_next() returns NULL token at end-of-stream.
                // Some llama.cpp builds signal this with EV_ERROR_STREAM_ENDED,
                // others with EV_SUCCESS (error code 0).  Both are clean exits.
                if (error != EV_ERROR_STREAM_ENDED && error != EV_SUCCESS) {
                    const char* error_msg = ev_error_string(error);
                    instance->last_error = error_msg;
                    LOGE("Stream error: %s", error_msg);
                    ev_stream_free(stream);
                    throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$GenerationError", error_msg);
                    return JNI_FALSE;
                }
                break;
            }

            jstring jtoken = string_to_jstring(env, token);
            ev_free_string(token);
            
            env->CallVoidMethod(callback, on_token_method, jtoken);
            env->DeleteLocalRef(jtoken);

            if (env->ExceptionCheck()) {
                env->ExceptionDescribe();
                env->ExceptionClear();
                LOGE("Exception during callback invocation (see above for details)");
                ev_stream_free(stream);
                return JNI_FALSE;
            }
        }

        ev_stream_free(stream);
        env->DeleteLocalRef(callback_class);
        LOGI("Streaming generation complete");
        return JNI_TRUE;

    } catch (const std::exception& e) {
        LOGE("Stream generation failed: %s", e.what());
        instance->last_error = e.what();
        throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$GenerationError", e.what());
        return JNI_FALSE;
    }
}

/**
 * Get current memory usage.
 */
JNIEXPORT jlong JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeGetMemoryUsage(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->initialized || !instance->context) {
        return -1;
    }

    try {
        ev_memory_stats stats;
        ev_error_t error = ev_get_memory_usage(instance->context, &stats);
        
        if (error != EV_SUCCESS) {
            LOGE("Failed to get memory usage: %s", ev_error_string(error));
            return -1;
        }

        return static_cast<jlong>(stats.current_bytes);

    } catch (const std::exception& e) {
        LOGE("Failed to get memory usage: %s", e.what());
        return -1;
    }
}

/**
 * Unload the model.
 */
JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeUnloadModel(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_instance(handle);
    if (!instance) return;

    try {
        std::lock_guard<std::mutex> lock(instance->mutex);

        if (instance->initialized && instance->context) {
            LOGI("Unloading model");
            
            ev_free(instance->context);
            instance->context = nullptr;
            instance->initialized = false;
            
            LOGI("Model unloaded successfully");
        }
    } catch (const std::exception& e) {
        LOGE("Failed to unload model: %s", e.what());
    }
}

/**
 * Dispose of the native instance.
 */
JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeDispose(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_instance(handle);
    if (!instance) return;

    try {
        LOGI("Disposing native instance");

        {
            std::lock_guard<std::mutex> lock(instance->mutex);
            if (instance->initialized && instance->context) {
                ev_free(instance->context);
                instance->context = nullptr;
                instance->initialized = false;
            }
        }

        delete instance;
        LOGI("Native instance disposed");

    } catch (const std::exception& e) {
        LOGE("Failed to dispose instance: %s", e.what());
        delete instance; // Try to delete anyway
    }
}

/* ============================================================================
 * Context Management Functions
 * ========================================================================= */

/**
 * Check if context is valid.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeIsValid(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->context) {
        return JNI_FALSE;
    }

    return ev_is_valid(instance->context) ? JNI_TRUE : JNI_FALSE;
}

/**
 * Reset context state (clear conversation history).
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeReset(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->context) {
        return JNI_FALSE;
    }

    try {
        std::lock_guard<std::mutex> lock(instance->mutex);
        ev_error_t error = ev_reset(instance->context);
        return (error == EV_SUCCESS) ? JNI_TRUE : JNI_FALSE;
    } catch (const std::exception& e) {
        LOGE("Failed to reset context: %s", e.what());
        return JNI_FALSE;
    }
}

/* ============================================================================
 * Memory Management Functions
 * ========================================================================= */

/**
 * Set memory limit for context.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeSetMemoryLimit(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle,
    jlong limit_bytes
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->context) {
        return JNI_FALSE;
    }

    try {
        ev_error_t error = ev_set_memory_limit(instance->context, static_cast<size_t>(limit_bytes));
        return (error == EV_SUCCESS) ? JNI_TRUE : JNI_FALSE;
    } catch (const std::exception& e) {
        LOGE("Failed to set memory limit: %s", e.what());
        return JNI_FALSE;
    }
}

/**
 * Manually trigger garbage collection and memory cleanup.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeMemoryCleanup(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->context) {
        return JNI_FALSE;
    }

    try {
        ev_error_t error = ev_memory_cleanup(instance->context);
        return (error == EV_SUCCESS) ? JNI_TRUE : JNI_FALSE;
    } catch (const std::exception& e) {
        LOGE("Failed to cleanup memory: %s", e.what());
        return JNI_FALSE;
    }
}

/**
 * Set memory pressure callback.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeSetMemoryPressureCallback(
    JNIEnv* env,
    jobject /* this */,
    jlong handle,
    jobject callback
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->context) {
        return JNI_FALSE;
    }

    try {
        std::lock_guard<std::mutex> lock(callback_mutex);
        
        if (callback != nullptr) {
            // Register callback
            JavaVM* jvm;
            if (env->GetJavaVM(&jvm) != JNI_OK) {
                LOGE("Failed to get JavaVM");
                return JNI_FALSE;
            }
            
            // Remove any existing callback for this context
            auto it = memory_callbacks.find(instance->context);
            if (it != memory_callbacks.end()) {
                env->DeleteGlobalRef(it->second.callback);
                memory_callbacks.erase(it);
            }
            
            // Store new callback as global reference
            jobject global_callback = env->NewGlobalRef(callback);
            if (!global_callback) {
                LOGE("Failed to create global reference");
                return JNI_FALSE;
            }
            
            memory_callbacks[instance->context] = {jvm, global_callback};
            
            // Register with C API
            ev_error_t error = ev_set_memory_pressure_callback(
                instance->context,
                memory_pressure_callback_trampoline,
                instance->context
            );
            
            if (error != EV_SUCCESS) {
                LOGE("Failed to set memory pressure callback: %s", ev_error_string(error));
                env->DeleteGlobalRef(global_callback);
                memory_callbacks.erase(instance->context);
                return JNI_FALSE;
            }
            
            LOGI("Memory pressure callback registered");
            return JNI_TRUE;
            
        } else {
            // Unregister callback
            auto it = memory_callbacks.find(instance->context);
            if (it != memory_callbacks.end()) {
                env->DeleteGlobalRef(it->second.callback);
                memory_callbacks.erase(it);
            }
            
            ev_error_t error = ev_set_memory_pressure_callback(instance->context, nullptr, nullptr);
            if (error != EV_SUCCESS) {
                LOGE("Failed to unregister memory pressure callback: %s", ev_error_string(error));
                return JNI_FALSE;
            }
            
            LOGI("Memory pressure callback unregistered");
            return JNI_TRUE;
        }
        
    } catch (const std::exception& e) {
        LOGE("Failed to set memory pressure callback: %s", e.what());
        return JNI_FALSE;
    }
}

/**
 * Get detailed memory statistics.
 */
JNIEXPORT jlongArray JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeGetMemoryStats(
    JNIEnv* env,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->context) {
        return nullptr;
    }

    try {
        ev_memory_stats stats;
        ev_error_t error = ev_get_memory_usage(instance->context, &stats);
        
        if (error != EV_SUCCESS) {
            LOGE("Failed to get memory stats: %s", ev_error_string(error));
            return nullptr;
        }

        // Return array: [current, peak, limit, model, context]
        jlongArray result = env->NewLongArray(5);
        if (result) {
            jlong values[5];
            values[0] = static_cast<jlong>(stats.current_bytes);
            values[1] = static_cast<jlong>(stats.peak_bytes);
            values[2] = static_cast<jlong>(stats.limit_bytes);
            values[3] = static_cast<jlong>(stats.model_bytes);
            values[4] = static_cast<jlong>(stats.context_bytes);
            env->SetLongArrayRegion(result, 0, 5, values);
        }

        return result;
    } catch (const std::exception& e) {
        LOGE("Failed to get memory stats: %s", e.what());
        return nullptr;
    }
}

/* ============================================================================
 * Model Information Functions
 * ========================================================================= */

/**
 * Get model metadata information.
 */
JNIEXPORT jobjectArray JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeGetModelInfo(
    JNIEnv* env,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_instance(handle);
    if (!instance || !instance->context) {
        return nullptr;
    }

    try {
        ev_model_info info;
        ev_error_t error = ev_get_model_info(instance->context, &info);
        
        if (error != EV_SUCCESS) {
            LOGE("Failed to get model info: %s", ev_error_string(error));
            return nullptr;
        }

        // Return string array: [name, architecture, num_params, context_length, embedding_dim, num_layers]
        jobjectArray result = env->NewObjectArray(6, env->FindClass("java/lang/String"), nullptr);
        if (result) {
            env->SetObjectArrayElement(result, 0, string_to_jstring(env, info.name ? info.name : ""));
            env->SetObjectArrayElement(result, 1, string_to_jstring(env, info.architecture ? info.architecture : ""));
            env->SetObjectArrayElement(result, 2, string_to_jstring(env, std::to_string(info.num_parameters)));
            env->SetObjectArrayElement(result, 3, string_to_jstring(env, std::to_string(info.context_length)));
            env->SetObjectArrayElement(result, 4, string_to_jstring(env, std::to_string(info.embedding_dim)));
            env->SetObjectArrayElement(result, 5, string_to_jstring(env, std::to_string(info.num_layers)));
        }

        return result;
    } catch (const std::exception& e) {
        LOGE("Failed to get model info: %s", e.what());
        return nullptr;
    }
}

/* ============================================================================
 * Backend Detection Functions
 * ========================================================================= */

/**
 * Detect the best available backend.
 */
JNIEXPORT jint JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeDetectBackend(
    JNIEnv* /* env */,
    jclass /* class */
) {
    return static_cast<jint>(ev_detect_backend());
}

/**
 * Check if a specific backend is available.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeIsBackendAvailable(
    JNIEnv* /* env */,
    jclass /* class */,
    jint backend
) {
    return ev_is_backend_available(static_cast<ev_backend_t>(backend)) ? JNI_TRUE : JNI_FALSE;
}

/**
 * Get human-readable name for backend type.
 */
JNIEXPORT jstring JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeGetBackendName(
    JNIEnv* env,
    jclass /* class */,
    jint backend
) {
    const char* name = ev_backend_name(static_cast<ev_backend_t>(backend));
    return string_to_jstring(env, name ? name : "Unknown");
}

/* ============================================================================
 * Utility Functions
 * ========================================================================= */

/**
 * Get the version string of the Edge Veda SDK.
 */
JNIEXPORT jstring JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeGetVersion(
    JNIEnv* env,
    jclass /* class */
) {
    return string_to_jstring(env, ev_version());
}

/**
 * Enable or disable verbose logging.
 */
JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeSetVerbose(
    JNIEnv* /* env */,
    jclass /* class */,
    jboolean enable
) {
    ev_set_verbose(enable == JNI_TRUE);
}

/* ============================================================================
 * Stream Control Functions
 * ========================================================================= */

/**
 * Cancel ongoing streaming generation.
 * Note: This requires storing the stream handle in EdgeVedaInstance.
 */
JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeCancelStream(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong stream_handle
) {
    if (stream_handle != 0) {
        ev_stream stream = reinterpret_cast<ev_stream>(stream_handle);
        ev_stream_cancel(stream);
    }
}

/* ============================================================================
 * Vision API Functions
 * ========================================================================= */

/**
 * Native vision instance structure.
 */
struct EdgeVedaVisionInstance {
    ev_vision_context context = nullptr;
    std::mutex mutex;
    bool initialized = false;
    std::string last_error;
};

/**
 * Get EdgeVedaVisionInstance from handle.
 */
EdgeVedaVisionInstance* get_vision_instance(jlong handle) {
    return reinterpret_cast<EdgeVedaVisionInstance*>(handle);
}

/**
 * Create a new vision instance.
 */
JNIEXPORT jlong JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeVisionCreate(
    JNIEnv* env,
    jobject /* this */
) {
    try {
        LOGI("Creating EdgeVeda vision instance");
        auto* instance = new EdgeVedaVisionInstance();
        return reinterpret_cast<jlong>(instance);
    } catch (const std::exception& e) {
        LOGE("Failed to create vision instance: %s", e.what());
        throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$NativeError", e.what());
        return 0;
    }
}

/**
 * Initialize vision context.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeVisionInit(
    JNIEnv* env,
    jobject /* this */,
    jlong handle,
    jstring model_path,
    jstring mmproj_path,
    jint num_threads,
    jint context_size,
    jint batch_size,
    jlong memory_limit_bytes,
    jint gpu_layers,
    jboolean use_mmap
) {
    auto* instance = get_vision_instance(handle);
    if (!instance) {
        throw_exception(env, "java/lang/IllegalStateException", "Invalid vision handle");
        return JNI_FALSE;
    }

    try {
        std::lock_guard<std::mutex> lock(instance->mutex);

        std::string model = jstring_to_string(env, model_path);
        std::string mmproj = jstring_to_string(env, mmproj_path);
        
        LOGI("Initializing vision model: %s", model.c_str());
        LOGI("Multimodal projector: %s", mmproj.c_str());

        // Configure vision context
        ev_vision_config config;
        ev_vision_config_default(&config);
        
        config.model_path = model.c_str();
        config.mmproj_path = mmproj.c_str();
        config.num_threads = num_threads > 0 ? num_threads : 0;
        config.context_size = context_size > 0 ? context_size : 0;
        config.batch_size = batch_size > 0 ? batch_size : 0;
        config.memory_limit_bytes = static_cast<size_t>(memory_limit_bytes);
        config.gpu_layers = gpu_layers;
        config.use_mmap = use_mmap;
        config.reserved = nullptr;

        // Initialize vision context
        ev_error_t error;
        instance->context = ev_vision_init(&config, &error);
        
        if (!instance->context) {
            const char* error_msg = ev_error_string(error);
            instance->last_error = error_msg;
            LOGE("Failed to initialize vision context: %s", error_msg);
            throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$ModelLoadError", error_msg);
            return JNI_FALSE;
        }

        instance->initialized = true;
        LOGI("Vision model initialized successfully");
        return JNI_TRUE;

    } catch (const std::exception& e) {
        LOGE("Vision initialization failed: %s", e.what());
        instance->last_error = e.what();
        throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$ModelLoadError", e.what());
        return JNI_FALSE;
    }
}

/**
 * Describe an image using the vision model.
 */
JNIEXPORT jstring JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeVisionDescribe(
    JNIEnv* env,
    jobject /* this */,
    jlong handle,
    jbyteArray image_bytes,
    jint width,
    jint height,
    jstring prompt,
    jint max_tokens,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jfloat repeat_penalty
) {
    auto* instance = get_vision_instance(handle);
    if (!instance || !instance->initialized || !instance->context) {
        throw_exception(env, "java/lang/IllegalStateException", "Vision model not initialized");
        return nullptr;
    }

    try {
        std::lock_guard<std::mutex> lock(instance->mutex);

        // Get image data
        jsize img_len = env->GetArrayLength(image_bytes);
        jbyte* img_data = env->GetByteArrayElements(image_bytes, nullptr);
        
        std::string prompt_str = jstring_to_string(env, prompt);
        LOGI("Describing image (%dx%d, %d bytes) with prompt: %s", width, height, img_len, prompt_str.c_str());

        // Configure generation parameters
        ev_generation_params params;
        ev_generation_params_default(&params);
        
        if (max_tokens > 0) params.max_tokens = max_tokens;
        if (temperature > 0) params.temperature = temperature;
        if (top_p > 0) params.top_p = top_p;
        if (top_k > 0) params.top_k = top_k;
        if (repeat_penalty > 0) params.repeat_penalty = repeat_penalty;

        // Describe image
        char* output = nullptr;
        ev_error_t error = ev_vision_describe(
            instance->context,
            reinterpret_cast<const unsigned char*>(img_data),
            width,
            height,
            prompt_str.c_str(),
            &params,
            &output
        );
        
        env->ReleaseByteArrayElements(image_bytes, img_data, JNI_ABORT);
        
        if (error != EV_SUCCESS || !output) {
            const char* error_msg = ev_error_string(error);
            instance->last_error = error_msg;
            LOGE("Vision description failed: %s", error_msg);
            throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$GenerationError", error_msg);
            return nullptr;
        }

        std::string result(output);
        ev_free_string(output);

        LOGI("Vision description complete (length: %zu)", result.length());
        return string_to_jstring(env, result);

    } catch (const std::exception& e) {
        LOGE("Vision description failed: %s", e.what());
        instance->last_error = e.what();
        throw_exception(env, "com/edgeveda/sdk/EdgeVedaException$GenerationError", e.what());
        return nullptr;
    }
}

/**
 * Check if vision context is valid.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeVisionIsValid(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_vision_instance(handle);
    if (!instance || !instance->context) {
        return JNI_FALSE;
    }

    return ev_vision_is_valid(instance->context) ? JNI_TRUE : JNI_FALSE;
}

/**
 * Get timing data from last vision inference.
 */
JNIEXPORT jdoubleArray JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeVisionGetLastTimings(
    JNIEnv* env,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_vision_instance(handle);
    if (!instance || !instance->context) {
        return nullptr;
    }

    try {
        ev_timings_data timings;
        ev_error_t error = ev_vision_get_last_timings(instance->context, &timings);
        
        if (error != EV_SUCCESS) {
            LOGE("Failed to get vision timings: %s", ev_error_string(error));
            return nullptr;
        }

        // Return array: [model_load_ms, image_encode_ms, prompt_eval_ms, decode_ms, prompt_tokens, generated_tokens]
        jdoubleArray result = env->NewDoubleArray(6);
        if (result) {
            jdouble values[6];
            values[0] = timings.model_load_ms;
            values[1] = timings.image_encode_ms;
            values[2] = timings.prompt_eval_ms;
            values[3] = timings.decode_ms;
            values[4] = static_cast<jdouble>(timings.prompt_tokens);
            values[5] = static_cast<jdouble>(timings.generated_tokens);
            env->SetDoubleArrayRegion(result, 0, 6, values);
        }

        return result;
    } catch (const std::exception& e) {
        LOGE("Failed to get vision timings: %s", e.what());
        return nullptr;
    }
}

/**
 * Free vision context.
 */
JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_nativeVisionDispose(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle
) {
    auto* instance = get_vision_instance(handle);
    if (!instance) return;

    try {
        LOGI("Disposing vision instance");

        {
            std::lock_guard<std::mutex> lock(instance->mutex);
            if (instance->initialized && instance->context) {
                ev_vision_free(instance->context);
                instance->context = nullptr;
                instance->initialized = false;
            }
        }

        delete instance;
        LOGI("Vision instance disposed");

    } catch (const std::exception& e) {
        LOGE("Failed to dispose vision instance: %s", e.what());
        delete instance; // Try to delete anyway
    }
}

} // extern "C"
