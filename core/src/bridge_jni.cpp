#include "edge_veda.h"
#include <android/log.h>
#include <jni.h>
#include <string>

#define TAG "EdgeVedaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Helper to convert Java String to std::string
std::string jstring2string(JNIEnv *env, jstring jStr) {
  if (!jStr)
    return "";
  const char *cstr = env->GetStringUTFChars(jStr, NULL);
  std::string str = cstr;
  env->ReleaseStringUTFChars(jStr, cstr);
  return str;
}

extern "C" {

// Get Edge Veda version
JNIEXPORT jstring JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_getVersionNative(JNIEnv *env,
                                                              jobject clazz) {
  const char *version = ev_version();
  return env->NewStringUTF(version);
}

// Initialize the engine
JNIEXPORT jlong JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_initContextNative(
    JNIEnv *env, jobject clazz, jstring jModelPath, jint numThreads,
    jint contextSize, jint batchSize) {
  std::string modelPath = jstring2string(env, jModelPath);
  LOGI("Initializing EdgeVeda with model: %s", modelPath.c_str());

  ev_config config;
  ev_config_default(&config);
  config.model_path = modelPath.c_str();
  config.num_threads = numThreads;
  config.context_size = contextSize;
  config.batch_size = batchSize;
  // Phase 1 Android: CPU-only backend
  config.backend = EV_BACKEND_CPU;

  // Safety defaults for mobile
  config.auto_unload_on_memory_pressure = true;

  ev_error_t error;
  ev_context ctx = ev_init(&config, &error);

  if (ctx == nullptr) {
    LOGE("Failed to initialize EdgeVeda: %s", ev_error_string(error));
    return 0; // Return 0 (NULL) to indicate failure
  }

  LOGI("EdgeVeda initialized successfully (CPU backend)");

  return reinterpret_cast<jlong>(ctx);
}

// Free the context
JNIEXPORT void JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_freeContextNative(
    JNIEnv *env, jobject clazz, jlong contextHandle) {
  if (contextHandle == 0)
    return;
  ev_context ctx = reinterpret_cast<ev_context>(contextHandle);
  ev_free(ctx);
  LOGI("EdgeVeda context freed");
}

// Generate text
JNIEXPORT jstring JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_generateNative(
    JNIEnv *env, jobject clazz, jlong contextHandle, jstring promptText,
    jint maxTokens) {
  if (contextHandle == 0)
    return env->NewStringUTF("");

  ev_context ctx = reinterpret_cast<ev_context>(contextHandle);
  std::string prompt = jstring2string(env, promptText);

  ev_generation_params params;
  ev_generation_params_default(&params);
  params.max_tokens = maxTokens;

  char *output = nullptr;
  ev_error_t result = ev_generate(ctx, prompt.c_str(), &params, &output);

  if (result != EV_SUCCESS || output == nullptr) {
    LOGE("Generation failed: %s", ev_error_string(result));
    return env->NewStringUTF("");
  }

  jstring jOutput = env->NewStringUTF(output);
  ev_free_string(output);
  return jOutput;
}

} // extern "C"
