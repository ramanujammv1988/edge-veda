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

// ============================================================================
// Whisper (Speech-to-Text) JNI Functions
// ============================================================================

// Get whisper version
JNIEXPORT jstring JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_whisperVersionNative(
    JNIEnv *env, jobject clazz) {
  const char *version = ev_version();
  return env->NewStringUTF(version);
}

// Initialize whisper context
JNIEXPORT jlong JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_whisperInitNative(
    JNIEnv *env, jobject clazz, jstring jModelPath, jint numThreads,
    jboolean useGpu) {
  std::string modelPath = jstring2string(env, jModelPath);
  LOGI("Initializing Whisper with model: %s", modelPath.c_str());

  ev_whisper_config config;
  ev_whisper_config_default(&config);
  config.model_path = modelPath.c_str();
  config.num_threads = numThreads;
  // Phase 2 Android: CPU-only backend (matching existing LLM pattern)
  config.use_gpu = false;

  ev_error_t error;
  ev_whisper_context ctx = ev_whisper_init(&config, &error);

  if (ctx == nullptr) {
    LOGE("Failed to initialize Whisper: %s", ev_error_string(error));
    return 0;
  }

  LOGI("Whisper initialized successfully (CPU backend)");
  return reinterpret_cast<jlong>(ctx);
}

// Transcribe audio to text
JNIEXPORT jstring JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_whisperTranscribeNative(
    JNIEnv *env, jobject clazz, jlong contextHandle, jfloatArray audioData,
    jint numSamples, jstring jLanguage) {
  if (contextHandle == 0)
    return env->NewStringUTF("");

  ev_whisper_context ctx = reinterpret_cast<ev_whisper_context>(contextHandle);

  // Get float array from JNI
  jfloat *samples = env->GetFloatArrayElements(audioData, NULL);
  if (samples == nullptr) {
    LOGE("Failed to get audio data array");
    return env->NewStringUTF("");
  }

  // Set up transcription parameters
  ev_whisper_params params;
  params.n_threads = 0; // Use config default
  std::string language = jstring2string(env, jLanguage);
  params.language = language.empty() ? "en" : language.c_str();
  params.translate = false;
  params.reserved = nullptr;

  // Transcribe
  ev_whisper_result result;
  ev_error_t err = ev_whisper_transcribe(ctx, samples, numSamples, &params, &result);

  // Release float array
  env->ReleaseFloatArrayElements(audioData, samples, JNI_ABORT);

  if (err != EV_SUCCESS) {
    LOGE("Whisper transcription failed: %s", ev_error_string(err));
    return env->NewStringUTF("");
  }

  // Concatenate all segment texts into single string
  std::string fullText;
  for (int i = 0; i < result.n_segments; i++) {
    if (result.segments[i].text != nullptr) {
      fullText += result.segments[i].text;
    }
  }

  jstring jOutput = env->NewStringUTF(fullText.c_str());

  // Free whisper result
  ev_whisper_free_result(&result);

  return jOutput;
}

// Free whisper context
JNIEXPORT void JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_whisperFreeNative(
    JNIEnv *env, jobject clazz, jlong contextHandle) {
  if (contextHandle == 0)
    return;
  ev_whisper_context ctx = reinterpret_cast<ev_whisper_context>(contextHandle);
  ev_whisper_free(ctx);
  LOGI("Whisper context freed");
}

// Check if whisper context is valid
JNIEXPORT jboolean JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_whisperIsValidNative(
    JNIEnv *env, jobject clazz, jlong contextHandle) {
  if (contextHandle == 0)
    return JNI_FALSE;
  ev_whisper_context ctx = reinterpret_cast<ev_whisper_context>(contextHandle);
  return ev_whisper_is_valid(ctx) ? JNI_TRUE : JNI_FALSE;
}

} // extern "C"
