#include <jni.h>
#include <string>
#include <android/log.h>
#include "edge_veda.h"

#define TAG "EdgeVedaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static jstring toJString(JNIEnv* env, const char* str) {
    return str ? env->NewStringUTF(str) : nullptr;
}

static std::string fromJString(JNIEnv* env, jstring str) {
    if (!str) return "";
    const char* chars = env->GetStringUTFChars(str, nullptr);
    std::string result(chars);
    env->ReleaseStringUTFChars(str, chars);
    return result;
}

static void throwException(JNIEnv* env, ev_error_t error) {
    const char* msg = ev_error_string(error);
    jclass cls = env->FindClass("com/edgeveda/sdk/EdgeVedaException");
    if (cls) {
        env->ThrowNew(cls, msg);
    }
}

extern "C" {

// --- Context Management ---

JNIEXPORT jlong JNICALL
Java_com_edgeveda_sdk_NativeBridge_evInit(
    JNIEnv* env, jclass, jstring modelPath, jint numThreads,
    jint contextSize, jint gpuLayers, jboolean useGpu, jint maxMemoryMb) {

    ev_config config;
    ev_config_default(&config);

    std::string path = fromJString(env, modelPath);
    config.model_path = path.c_str();
    config.num_threads = numThreads;
    config.context_size = contextSize;
    config.gpu_layers = gpuLayers;
    config.memory_limit_bytes = static_cast<size_t>(maxMemoryMb) * 1024 * 1024;

    ev_error_t error;
    ev_context ctx = ev_init(&config, &error);

    if (!ctx) {
        throwException(env, error);
        return 0;
    }

    LOGI("Context initialized: %p", ctx);
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_NativeBridge_evFree(JNIEnv*, jclass, jlong handle) {
    auto ctx = reinterpret_cast<ev_context>(handle);
    if (ctx) {
        ev_free(ctx);
        LOGI("Context freed");
    }
}

// --- Single-Shot Generation ---

JNIEXPORT jstring JNICALL
Java_com_edgeveda_sdk_NativeBridge_evGenerate(
    JNIEnv* env, jclass, jlong handle, jstring prompt,
    jint maxTokens, jfloat temperature, jfloat topP, jint topK,
    jfloat repeatPenalty, jfloat confidenceThreshold) {

    auto ctx = reinterpret_cast<ev_context>(handle);
    std::string promptStr = fromJString(env, prompt);

    ev_generation_params params;
    ev_generation_params_default(&params);
    params.max_tokens = maxTokens;
    params.temperature = temperature;
    params.top_p = topP;
    params.top_k = topK;
    params.repeat_penalty = repeatPenalty;
    params.confidence_threshold = confidenceThreshold;

    char* output = nullptr;
    ev_error_t error = ev_generate(ctx, promptStr.c_str(), &params, &output);

    if (error != EV_SUCCESS) {
        throwException(env, error);
        return nullptr;
    }

    jstring result = toJString(env, output);
    ev_free_string(output);
    return result;
}

// --- Streaming Generation ---

JNIEXPORT jlong JNICALL
Java_com_edgeveda_sdk_NativeBridge_evGenerateStream(
    JNIEnv* env, jclass, jlong handle, jstring prompt,
    jint maxTokens, jfloat temperature, jfloat topP, jint topK,
    jfloat repeatPenalty, jfloat confidenceThreshold) {

    auto ctx = reinterpret_cast<ev_context>(handle);
    std::string promptStr = fromJString(env, prompt);

    ev_generation_params params;
    ev_generation_params_default(&params);
    params.max_tokens = maxTokens;
    params.temperature = temperature;
    params.top_p = topP;
    params.top_k = topK;
    params.repeat_penalty = repeatPenalty;
    params.confidence_threshold = confidenceThreshold;

    ev_error_t error;
    ev_stream stream = ev_generate_stream(ctx, promptStr.c_str(), &params, &error);

    if (!stream) {
        throwException(env, error);
        return 0;
    }

    return reinterpret_cast<jlong>(stream);
}

JNIEXPORT jstring JNICALL
Java_com_edgeveda_sdk_NativeBridge_evStreamNext(JNIEnv* env, jclass, jlong handle) {
    auto stream = reinterpret_cast<ev_stream>(handle);
    ev_error_t error;
    char* token = ev_stream_next(stream, &error);

    if (!token) return nullptr;

    jstring result = toJString(env, token);
    ev_free_string(token);
    return result;
}

JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_NativeBridge_evStreamCancel(JNIEnv*, jclass, jlong handle) {
    auto stream = reinterpret_cast<ev_stream>(handle);
    if (stream) ev_stream_cancel(stream);
}

JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_NativeBridge_evStreamFree(JNIEnv*, jclass, jlong handle) {
    auto stream = reinterpret_cast<ev_stream>(handle);
    if (stream) ev_stream_free(stream);
}

// --- Memory ---

JNIEXPORT jlongArray JNICALL
Java_com_edgeveda_sdk_NativeBridge_evGetMemoryUsage(JNIEnv* env, jclass, jlong handle) {
    auto ctx = reinterpret_cast<ev_context>(handle);
    ev_memory_stats stats;
    ev_error_t error = ev_get_memory_usage(ctx, &stats);

    if (error != EV_SUCCESS) {
        throwException(env, error);
        return nullptr;
    }

    jlong data[5] = {
        static_cast<jlong>(stats.current_bytes),
        static_cast<jlong>(stats.peak_bytes),
        static_cast<jlong>(stats.limit_bytes),
        static_cast<jlong>(stats.model_bytes),
        static_cast<jlong>(stats.context_bytes),
    };

    jlongArray result = env->NewLongArray(5);
    env->SetLongArrayRegion(result, 0, 5, data);
    return result;
}

// --- Embeddings ---

JNIEXPORT jfloatArray JNICALL
Java_com_edgeveda_sdk_NativeBridge_evEmbed(JNIEnv* env, jclass, jlong handle, jstring text) {
    auto ctx = reinterpret_cast<ev_context>(handle);
    std::string textStr = fromJString(env, text);

    ev_embed_result result;
    ev_error_t error = ev_embed(ctx, textStr.c_str(), &result);

    if (error != EV_SUCCESS) {
        throwException(env, error);
        return nullptr;
    }

    jfloatArray arr = env->NewFloatArray(result.dimensions);
    env->SetFloatArrayRegion(arr, 0, result.dimensions, result.embeddings);
    ev_free_embeddings(&result);
    return arr;
}

// --- Version ---

JNIEXPORT jstring JNICALL
Java_com_edgeveda_sdk_NativeBridge_evVersion(JNIEnv* env, jclass) {
    return toJString(env, ev_version());
}

} // extern "C"
