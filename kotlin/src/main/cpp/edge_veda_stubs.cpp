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

/* ============================================================================
 * NEW: Advanced Features (Added for Kotlin SDK Parity)
 * ========================================================================= */

/**
 * @brief Cancel ongoing inference operation
 * 
 * This stub allows cancellation to be called but has no effect
 * since there's no real inference happening.
 * 
 * @param ctx Context handle
 * @return Always returns false (no operation to cancel)
 */
EV_API bool ev_cancel(ev_context ctx) {
    (void)ctx;
    return false;
}

/**
 * @brief Set system prompt for conversation
 * 
 * @param ctx Context handle
 * @param prompt System prompt text
 * @return Always returns false (stub build)
 */
EV_API bool ev_set_system_prompt(ev_context ctx, const char* prompt) {
    (void)ctx;
    (void)prompt;
    return false;
}

/**
 * @brief Clear conversation history while keeping system prompt
 * 
 * @param ctx Context handle
 * @return Always returns false (stub build)
 */
EV_API bool ev_clear_chat_history(ev_context ctx) {
    (void)ctx;
    return false;
}

/**
 * @brief Get total context size (token capacity)
 * 
 * @param ctx Context handle
 * @return Always returns 0 (stub build)
 */
EV_API int ev_get_context_size(ev_context ctx) {
    (void)ctx;
    return 0;
}

/**
 * @brief Get number of tokens currently used in context
 * 
 * @param ctx Context handle
 * @return Always returns 0 (stub build)
 */
EV_API int ev_get_context_used(ev_context ctx) {
    (void)ctx;
    return 0;
}

/**
 * @brief Tokenize text into token IDs
 * 
 * @param ctx Context handle
 * @param text Input text
 * @param tokens Output pointer for token array (caller must free with ev_free_tokens)
 * @param n_tokens Output pointer for number of tokens
 * @return Always returns EV_ERROR_NOT_IMPLEMENTED (stub build)
 */
EV_API ev_error_t ev_tokenize(
    ev_context ctx,
    const char* text,
    int** tokens,
    int* n_tokens
) {
    (void)ctx;
    (void)text;
    if (tokens) *tokens = nullptr;
    if (n_tokens) *n_tokens = 0;
    return EV_ERROR_NOT_IMPLEMENTED;
}

/**
 * @brief Convert token IDs back to text
 * 
 * @param ctx Context handle
 * @param tokens Array of token IDs
 * @param n_tokens Number of tokens
 * @param output Output pointer for text (caller must free with ev_free_string)
 * @return Always returns EV_ERROR_NOT_IMPLEMENTED (stub build)
 */
EV_API ev_error_t ev_detokenize(
    ev_context ctx,
    const int* tokens,
    int n_tokens,
    char** output
) {
    (void)ctx;
    (void)tokens;
    (void)n_tokens;
    if (output) *output = nullptr;
    return EV_ERROR_NOT_IMPLEMENTED;
}

/**
 * @brief Free token array allocated by ev_tokenize
 * 
 * @param tokens Token array to free
 */
EV_API void ev_free_tokens(int* tokens) {
    free(tokens);
}

/**
 * @brief Get embedding vector for text
 * 
 * @param ctx Context handle
 * @param text Input text
 * @param embedding Output pointer for embedding array (caller must free with ev_free_embedding)
 * @param dimensions Output pointer for embedding dimensions
 * @return Always returns EV_ERROR_NOT_IMPLEMENTED (stub build)
 */
EV_API ev_error_t ev_get_embedding(
    ev_context ctx,
    const char* text,
    float** embedding,
    int* dimensions
) {
    (void)ctx;
    (void)text;
    if (embedding) *embedding = nullptr;
    if (dimensions) *dimensions = 0;
    return EV_ERROR_NOT_IMPLEMENTED;
}

/**
 * @brief Free embedding array allocated by ev_get_embedding
 * 
 * @param embedding Embedding array to free
 */
EV_API void ev_free_embedding(float* embedding) {
    free(embedding);
}

/**
 * @brief Save conversation session to file
 * 
 * @param ctx Context handle
 * @param path File path to save session
 * @return Always returns false (stub build)
 */
EV_API bool ev_save_session(ev_context ctx, const char* path) {
    (void)ctx;
    (void)path;
    return false;
}

/**
 * @brief Load conversation session from file
 * 
 * @param ctx Context handle
 * @param path File path to load session from
 * @return Always returns false (stub build)
 */
EV_API bool ev_load_session(ev_context ctx, const char* path) {
    (void)ctx;
    (void)path;
    return false;
}

/**
 * @brief Run performance benchmark
 * 
 * @param ctx Context handle
 * @param n_threads Number of threads to use
 * @param n_tokens Number of tokens to benchmark
 * @param results Output array for benchmark results [prompt_ms, decode_ms, total_ms]
 * @return Always returns false (stub build)
 */
EV_API bool ev_bench(ev_context ctx, int n_threads, int n_tokens, double* results) {
    (void)ctx;
    (void)n_threads;
    (void)n_tokens;
    if (results) {
        results[0] = 0.0;  // prompt_ms
        results[1] = 0.0;  // decode_ms
        results[2] = 0.0;  // total_ms
    }
    return false;
}

/* ============================================================================
 * Stream Token Info (Confidence Scoring)
 * ========================================================================= */

/**
 * @brief Get extended token information from stream
 * 
 * @param stream Stream handle
 * @param info Output pointer for token info structure
 * @return Always returns EV_ERROR_NOT_IMPLEMENTED (stub build)
 */
EV_API ev_error_t ev_stream_get_token_info(
    ev_stream stream,
    ev_stream_token_info* info
) {
    (void)stream;
    if (info) {
        memset(info, 0, sizeof(ev_stream_token_info));
        info->confidence = -1.0f;
        info->avg_confidence = -1.0f;
        info->needs_cloud_handoff = false;
        info->token_index = 0;
    }
    return EV_ERROR_NOT_IMPLEMENTED;
}

/* ============================================================================
 * Embeddings API
 * ========================================================================= */

/**
 * @brief Compute text embeddings
 * 
 * @param ctx Context handle
 * @param text Input text to embed
 * @param result Output pointer for embedding result
 * @return Always returns EV_ERROR_NOT_IMPLEMENTED (stub build)
 */
EV_API ev_error_t ev_embed(
    ev_context ctx,
    const char* text,
    ev_embed_result* result
) {
    (void)ctx;
    (void)text;
    if (result) {
        memset(result, 0, sizeof(ev_embed_result));
    }
    return EV_ERROR_NOT_IMPLEMENTED;
}

/**
 * @brief Free embedding result
 * 
 * @param result Pointer to result structure to free
 */
EV_API void ev_free_embeddings(ev_embed_result* result) {
    if (!result) return;
    if (result->embeddings) {
        free(result->embeddings);
    }
    memset(result, 0, sizeof(ev_embed_result));
}

/* ============================================================================
 * Whisper API (Speech-to-Text)
 * ========================================================================= */

/**
 * @brief Get default whisper configuration
 * 
 * @param config Pointer to configuration structure to fill
 */
EV_API void ev_whisper_config_default(ev_whisper_config* config) {
    if (!config) return;
    memset(config, 0, sizeof(ev_whisper_config));
    config->model_path = nullptr;
    config->num_threads = 0;
    config->use_gpu = true;
    config->reserved = nullptr;
}

/**
 * @brief Initialize whisper context for speech-to-text
 * 
 * @param config Whisper configuration
 * @param error Optional pointer to receive error code
 * @return Always returns nullptr (stub build)
 */
EV_API ev_whisper_context ev_whisper_init(
    const ev_whisper_config* config,
    ev_error_t* error
) {
    (void)config;
    if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
    return nullptr;
}

/**
 * @brief Transcribe PCM audio samples to text
 * 
 * @param ctx Whisper context handle
 * @param pcm_samples PCM audio data (16kHz, mono, float32, range [-1.0, 1.0])
 * @param n_samples Number of samples
 * @param params Transcription parameters
 * @param result Output pointer for transcription result (caller must free with ev_whisper_free_result)
 * @return Always returns EV_ERROR_MODEL_LOAD_FAILED (stub build)
 */
EV_API ev_error_t ev_whisper_transcribe(
    ev_whisper_context ctx,
    const float* pcm_samples,
    int n_samples,
    const ev_whisper_params* params,
    ev_whisper_result* result
) {
    (void)ctx;
    (void)pcm_samples;
    (void)n_samples;
    (void)params;
    if (result) {
        memset(result, 0, sizeof(ev_whisper_result));
    }
    return EV_ERROR_MODEL_LOAD_FAILED;
}

/**
 * @brief Free whisper transcription result
 * 
 * @param result Pointer to result structure to free
 */
EV_API void ev_whisper_free_result(ev_whisper_result* result) {
    if (!result) return;
    if (result->segments) {
        // Free each segment's text
        for (int i = 0; i < result->n_segments; i++) {
            free((void*)result->segments[i].text);
        }
        free(result->segments);
    }
    memset(result, 0, sizeof(ev_whisper_result));
}

/**
 * @brief Free whisper context
 * 
 * @param ctx Whisper context handle
 */
EV_API void ev_whisper_free(ev_whisper_context ctx) {
    (void)ctx;
}

/**
 * @brief Check if whisper context is valid
 * 
 * @param ctx Whisper context handle
 * @return Always returns false (stub build)
 */
EV_API bool ev_whisper_is_valid(ev_whisper_context ctx) {
    (void)ctx;
    return false;
}

#ifdef __cplusplus
}
#endif
