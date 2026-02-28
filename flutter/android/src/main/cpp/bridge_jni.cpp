#include "edge_veda.h"
#include <jni.h>
#include <string>

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_getVersionNative(JNIEnv *env,
                                                             jobject thiz) {
  const char *version = ev_version();
  return env->NewStringUTF(version);
}

JNIEXPORT jlong JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_initContextNative(
    JNIEnv *env, jobject thiz, jstring modelPath, jint numThreads,
    jint contextSize, jint batchSize) {
  const char *model_path_chars = env->GetStringUTFChars(modelPath, nullptr);

  ev_config config;
  ev_config_default(&config);
  config.model_path = model_path_chars;
  config.num_threads = numThreads;
  config.context_size = contextSize;
  config.batch_size = batchSize;

  ev_error_t error;
  ev_context ctx = ev_init(&config, &error);

  env->ReleaseStringUTFChars(modelPath, model_path_chars);

  if (error != 0 || !ev_is_valid(ctx)) {
    if (ctx)
      ev_free(ctx);
    return 0; // Return null pointer internally handled by Kotlin
  }

  return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT void JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_freeContextNative(
    JNIEnv *env, jobject thiz, jlong contextHandle) {
  ev_context ctx = reinterpret_cast<ev_context>(contextHandle);
  if (ctx) {
    ev_free(ctx);
  }
}

JNIEXPORT jstring JNICALL
Java_com_edgeveda_edge_1veda_NativeEdgeVeda_generateNative(JNIEnv *env,
                                                           jobject thiz,
                                                           jlong contextHandle,
                                                           jstring promptText,
                                                           jint maxTokens) {
  ev_context ctx = reinterpret_cast<ev_context>(contextHandle);
  if (!ctx)
    return env->NewStringUTF("");

  const char *prompt_chars = env->GetStringUTFChars(promptText, nullptr);

  ev_generation_params params;
  ev_generation_params_default(&params);
  params.max_tokens = maxTokens;

  char *output = nullptr;
  ev_error_t result = ev_generate(ctx, prompt_chars, &params, &output);

  env->ReleaseStringUTFChars(promptText, prompt_chars);

  if (result == 0 && output != nullptr) {
    jstring final_output = env->NewStringUTF(output);
    ev_free_string(output);
    return final_output;
  }

  if (output)
    ev_free_string(output);
  return env->NewStringUTF("");
}
}
