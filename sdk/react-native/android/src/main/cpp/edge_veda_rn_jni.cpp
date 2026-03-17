#include <jni.h>
#include <string>
#include <android/log.h>
#include "edge_veda.h"

#define TAG "EdgeVedaRN"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_edgeveda_reactnative_EdgeVedaModule_nativeInit(
    JNIEnv* env, jobject, jstring modelPath, jint numThreads,
    jint contextSize, jint gpuLayers) {

    const char* path = env->GetStringUTFChars(modelPath, nullptr);

    ev_config config;
    ev_config_default(&config);
    config.model_path = path;
    config.num_threads = numThreads;
    config.context_size = contextSize;
    config.gpu_layers = gpuLayers;

    ev_error_t error;
    ev_context ctx = ev_init(&config, &error);
    env->ReleaseStringUTFChars(modelPath, path);

    if (!ctx) {
        LOGE("Init failed: %s", ev_error_string(error));
        return 0;
    }
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT jstring JNICALL
Java_com_edgeveda_reactnative_EdgeVedaModule_nativeGenerate(
    JNIEnv* env, jobject, jlong handle, jstring prompt,
    jint maxTokens, jfloat temperature) {

    auto ctx = reinterpret_cast<ev_context>(handle);
    const char* promptStr = env->GetStringUTFChars(prompt, nullptr);

    ev_generation_params params;
    ev_generation_params_default(&params);
    params.max_tokens = maxTokens;
    params.temperature = temperature;

    char* output = nullptr;
    ev_error_t error = ev_generate(ctx, promptStr, &params, &output);
    env->ReleaseStringUTFChars(prompt, promptStr);

    if (error != EV_SUCCESS || !output) return nullptr;

    jstring result = env->NewStringUTF(output);
    ev_free_string(output);
    return result;
}

JNIEXPORT void JNICALL
Java_com_edgeveda_reactnative_EdgeVedaModule_nativeFree(
    JNIEnv*, jobject, jlong handle) {
    auto ctx = reinterpret_cast<ev_context>(handle);
    if (ctx) ev_free(ctx);
}

} // extern "C"
