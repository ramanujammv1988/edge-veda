/**
 * @file edge_veda_stubs.cpp
 * @brief Stub implementations of the Edge Veda C API for Android builds
 *
 * These stubs allow the JNI library to compile and link without the real
 * libedge_veda native library (which requires llama.cpp submodule).
 * All functions return error codes or safe defaults.
 */

#include "../../../../core/include/edge_veda.h"
#include <cstring>
#include <cstdlib>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Version Information
 * ========================================================================= */

EV_API const char* ev_version(void) {
    return "1.0.0-stub";
}

/* ============================================================================
 * Error Codes
 * ========================================================================= */

EV_API const char* ev_error_string(ev_error_t error) {
    switch (error) {
        case EV_SUCCESS:                    return "Success";
        case EV_ERROR_INVALID_PARAM:        return "Invalid parameter";
        case EV_ERROR_OUT_OF_MEMORY:        return "Out of memory";
        case EV_ERROR_MODEL_LOAD_FAILED:    return "Model load failed (stub build - no native engine)";
        case EV_ERROR_BACKEND_INIT_FAILED:  return "Backend initialization failed";
        case EV_ERROR_INFERENCE_FAILED:     return "Inference failed";
        case EV_ERROR_CONTEXT_INVALID:      return "Invalid context";
        case EV_ERROR_STREAM_ENDED:         return "Stream ended";
        case EV_ERROR_NOT_IMPLEMENTED:      return "Not implemented";
        case EV_ERROR_MEMORY_LIMIT_EXCEEDED: return "Memory limit exceeded";
        case EV_ERROR_UNSUPPORTED_BACKEND:  return "Unsupported backend";
        case EV_ERROR_UNKNOWN:              return "Unknown error";
        default:                            return "Unknown error code";
    }
}

/* ============================================================================
 * Backend Types
 * ========================================================================= */

EV_API ev_backend_t ev_detect_backend(void) {
    return EV_BACKEND_CPU;
}

EV_API bool ev_is_backend_available(ev_backend_t backend) {
    return backend == EV_BACKEND_CPU;
}

EV_API const char* ev_backend_name(ev_backend_t backend) {
    switch (backend) {
        case EV_BACKEND_AUTO:   return "Auto";
        case EV_BACKEND_METAL:  return "Metal";
        case EV_BACKEND_VULKAN: return "Vulkan";
        case EV_BACKEND_CPU:    return "CPU";
        default:                return "Unknown";
    }
}

/* ============================================================================
 * Configuration
 * ========================================================================= */

EV_API void ev_config_default(ev_config* config) {
    if (!config) return;
    memset(config, 0, sizeof(ev_config));
    config->model_path = nullptr;
    config->backend = EV_BACKEND_AUTO;
    config->num_threads = 0;
    config->context_size = 2048;
    config->batch_size = 512;
    config->memory_limit_bytes = 0;
    config->auto_unload_on_memory_pressure = false;
    config->gpu_layers = -1;
    config->use_mmap = true;
    config->use_mlock = false;
    config->seed = -1;
    config->reserved = nullptr;
}

/* ============================================================================
 * Context Management
 * ========================================================================= */

EV_API ev_context ev_init(const ev_config* config, ev_error_t* error) {
    (void)config;
    if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
    return nullptr;
}

EV_API void ev_free(ev_context ctx) {
    (void)ctx;
}

EV_API bool ev_is_valid(ev_context ctx) {
    (void)ctx;
    return false;
}

/* ============================================================================
 * Generation Parameters
 * ========================================================================= */

EV_API void ev_generation_params_default(ev_generation_params* params) {
    if (!params) return;
    memset(params, 0, sizeof(ev_generation_params));
    params->max_tokens = 256;
    params->temperature = 0.7f;
    params->top_p = 0.9f;
    params->top_k = 40;
    params->repeat_penalty = 1.1f;
    params->frequency_penalty = 0.0f;
    params->presence_penalty = 0.0f;
    params->stop_sequences = nullptr;
    params->num_stop_sequences = 0;
    params->reserved = nullptr;
}

/* ============================================================================
 * Single-Shot Generation
 * ========================================================================= */

EV_API ev_error_t ev_generate(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    char** output
) {
    (void)ctx;
    (void)prompt;
    (void)params;
    (void)output;
    return EV_ERROR_MODEL_LOAD_FAILED;
}

EV_API void ev_free_string(char* str) {
    free(str);
}

/* ============================================================================
 * Streaming Generation
 * ========================================================================= */

EV_API ev_stream ev_generate_stream(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    ev_error_t* error
) {
    (void)ctx;
    (void)prompt;
    (void)params;
    if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
    return nullptr;
}

EV_API char* ev_stream_next(ev_stream stream, ev_error_t* error) {
    (void)stream;
    if (error) *error = EV_ERROR_STREAM_ENDED;
    return nullptr;
}

EV_API bool ev_stream_has_next(ev_stream stream) {
    (void)stream;
    return false;
}

EV_API void ev_stream_cancel(ev_stream stream) {
    (void)stream;
}

EV_API void ev_stream_free(ev_stream stream) {
    (void)stream;
}

/* ============================================================================
 * Memory Management
 * ========================================================================= */

EV_API ev_error_t ev_get_memory_usage(ev_context ctx, ev_memory_stats* stats) {
    (void)ctx;
    if (!stats) return EV_ERROR_INVALID_PARAM;
    memset(stats, 0, sizeof(ev_memory_stats));
    return EV_SUCCESS;
}

EV_API ev_error_t ev_set_memory_limit(ev_context ctx, size_t limit_bytes) {
    (void)ctx;
    (void)limit_bytes;
    return EV_SUCCESS;
}

EV_API ev_error_t ev_set_memory_pressure_callback(
    ev_context ctx,
    ev_memory_pressure_callback callback,
    void* user_data
) {
    (void)ctx;
    (void)callback;
    (void)user_data;
    return EV_SUCCESS;
}

EV_API ev_error_t ev_memory_cleanup(ev_context ctx) {
    (void)ctx;
    return EV_SUCCESS;
}

/* ============================================================================
 * Model Information
 * ========================================================================= */

EV_API ev_error_t ev_get_model_info(ev_context ctx, ev_model_info* info) {
    (void)ctx;
    if (!info) return EV_ERROR_INVALID_PARAM;
    memset(info, 0, sizeof(ev_model_info));
    info->name = "stub";
    info->architecture = "none";
    return EV_SUCCESS;
}

/* ============================================================================
 * Utility Functions
 * ========================================================================= */

EV_API void ev_set_verbose(bool enable) {
    (void)enable;
}

EV_API const char* ev_get_last_error(ev_context ctx) {
    (void)ctx;
    return "Stub build - native engine not available";
}

EV_API ev_error_t ev_reset(ev_context ctx) {
    (void)ctx;
    return EV_SUCCESS;
}

/* ============================================================================
 * Vision API
 * ========================================================================= */

EV_API void ev_vision_config_default(ev_vision_config* config) {
    if (!config) return;
    memset(config, 0, sizeof(ev_vision_config));
    config->model_path = nullptr;
    config->mmproj_path = nullptr;
    config->num_threads = 0;
    config->context_size = 0;
    config->batch_size = 0;
    config->memory_limit_bytes = 0;
    config->gpu_layers = -1;
    config->use_mmap = true;
    config->reserved = nullptr;
}

EV_API ev_vision_context ev_vision_init(
    const ev_vision_config* config,
    ev_error_t* error
) {
    (void)config;
    if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
    return nullptr;
}

EV_API ev_error_t ev_vision_describe(
    ev_vision_context ctx,
    const unsigned char* image_bytes,
    int width,
    int height,
    const char* prompt,
    const ev_generation_params* params,
    char** output
) {
    (void)ctx;
    (void)image_bytes;
    (void)width;
    (void)height;
    (void)prompt;
    (void)params;
    (void)output;
    return EV_ERROR_MODEL_LOAD_FAILED;
}

EV_API void ev_vision_free(ev_vision_context ctx) {
    (void)ctx;
}

EV_API bool ev_vision_is_valid(ev_vision_context ctx) {
    (void)ctx;
    return false;
}

EV_API ev_error_t ev_vision_get_last_timings(
    ev_vision_context ctx,
    ev_timings_data* timings
) {
    (void)ctx;
    if (!timings) return EV_ERROR_INVALID_PARAM;
    memset(timings, 0, sizeof(ev_timings_data));
    return EV_SUCCESS;
}

#ifdef __cplusplus
}
#endif