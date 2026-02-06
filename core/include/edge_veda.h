/**
 * @file edge_veda.h
 * @brief Edge Veda SDK - Public C API
 *
 * This header provides the public C API for the Edge Veda SDK,
 * enabling on-device AI inference across multiple platforms
 * (iOS, Android, Web, Flutter, React Native).
 *
 * @version 1.0.0
 * @copyright Copyright (c) 2026 Edge Veda
 */

#ifndef EDGE_VEDA_H
#define EDGE_VEDA_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* Symbol visibility for FFI/dlsym access */
#if defined(_WIN32) || defined(__CYGWIN__)
#  ifdef EV_BUILD_SHARED
#    define EV_API __declspec(dllexport)
#  else
#    define EV_API __declspec(dllimport)
#  endif
#else
#  define EV_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Version Information
 * ========================================================================= */

#define EDGE_VEDA_VERSION_MAJOR 1
#define EDGE_VEDA_VERSION_MINOR 0
#define EDGE_VEDA_VERSION_PATCH 0

/**
 * @brief Get the version string of the Edge Veda SDK
 * @return Version string in format "MAJOR.MINOR.PATCH"
 */
EV_API const char* ev_version(void);

/* ============================================================================
 * Error Codes
 * ========================================================================= */

typedef enum {
    EV_SUCCESS = 0,                    /**< Operation successful */
    EV_ERROR_INVALID_PARAM = -1,       /**< Invalid parameter provided */
    EV_ERROR_OUT_OF_MEMORY = -2,       /**< Out of memory */
    EV_ERROR_MODEL_LOAD_FAILED = -3,   /**< Failed to load model */
    EV_ERROR_BACKEND_INIT_FAILED = -4, /**< Failed to initialize backend */
    EV_ERROR_INFERENCE_FAILED = -5,    /**< Inference operation failed */
    EV_ERROR_CONTEXT_INVALID = -6,     /**< Invalid context */
    EV_ERROR_STREAM_ENDED = -7,        /**< Stream has ended */
    EV_ERROR_NOT_IMPLEMENTED = -8,     /**< Feature not implemented */
    EV_ERROR_MEMORY_LIMIT_EXCEEDED = -9, /**< Memory limit exceeded */
    EV_ERROR_UNSUPPORTED_BACKEND = -10, /**< Backend not supported on this platform */
    EV_ERROR_UNKNOWN = -999            /**< Unknown error */
} ev_error_t;

/**
 * @brief Get human-readable error message for error code
 * @param error Error code
 * @return Error message string
 */
EV_API const char* ev_error_string(ev_error_t error);

/* ============================================================================
 * Backend Types
 * ========================================================================= */

typedef enum {
    EV_BACKEND_AUTO = 0,    /**< Automatically detect best backend */
    EV_BACKEND_METAL = 1,   /**< Metal (iOS/macOS) */
    EV_BACKEND_VULKAN = 2,  /**< Vulkan (Android) */
    EV_BACKEND_CPU = 3      /**< CPU fallback */
} ev_backend_t;

/**
 * @brief Detect the best available backend for current platform
 * @return The recommended backend type
 */
EV_API ev_backend_t ev_detect_backend(void);

/**
 * @brief Check if a specific backend is available
 * @param backend Backend type to check
 * @return true if available, false otherwise
 */
EV_API bool ev_is_backend_available(ev_backend_t backend);

/**
 * @brief Get human-readable name for backend type
 * @param backend Backend type
 * @return Backend name string
 */
EV_API const char* ev_backend_name(ev_backend_t backend);

/* ============================================================================
 * Configuration
 * ========================================================================= */

/**
 * @brief Configuration structure for initializing Edge Veda context
 */
typedef struct {
    /** Model file path (GGUF format) */
    const char* model_path;

    /** Backend to use (use EV_BACKEND_AUTO for automatic detection) */
    ev_backend_t backend;

    /** Number of threads for CPU backend (0 = auto-detect) */
    int num_threads;

    /** Context size (number of tokens) */
    int context_size;

    /** Batch size for processing */
    int batch_size;

    /** Memory limit in bytes (0 = no limit) */
    size_t memory_limit_bytes;

    /** Enable memory auto-unload when limit is reached */
    bool auto_unload_on_memory_pressure;

    /** GPU layers to offload (-1 = all, 0 = none, >0 = specific count) */
    int gpu_layers;

    /** Use memory mapping for model file */
    bool use_mmap;

    /** Lock model in memory (prevent swapping) */
    bool use_mlock;

    /** Seed for random number generation (-1 = random) */
    int seed;

    /** Reserved for future use - must be NULL */
    void* reserved;
} ev_config;

/**
 * @brief Get default configuration with recommended settings
 * @param config Pointer to config structure to fill
 */
EV_API void ev_config_default(ev_config* config);

/* ============================================================================
 * Context Management
 * ========================================================================= */

/**
 * @brief Opaque context handle for Edge Veda inference engine
 */
typedef struct ev_context_impl* ev_context;

/**
 * @brief Initialize Edge Veda context with configuration
 * @param config Configuration structure
 * @param error Optional pointer to receive error code
 * @return Context handle on success, NULL on failure
 */
EV_API ev_context ev_init(const ev_config* config, ev_error_t* error);

/**
 * @brief Free Edge Veda context and release all resources
 * @param ctx Context handle to free
 */
EV_API void ev_free(ev_context ctx);

/**
 * @brief Check if context is valid and ready for inference
 * @param ctx Context handle
 * @return true if valid, false otherwise
 */
EV_API bool ev_is_valid(ev_context ctx);

/* ============================================================================
 * Generation Parameters
 * ========================================================================= */

/**
 * @brief Parameters for text generation
 */
typedef struct {
    /** Maximum number of tokens to generate */
    int max_tokens;

    /** Temperature for sampling (0.0 = deterministic, higher = more random) */
    float temperature;

    /** Top-p (nucleus) sampling threshold */
    float top_p;

    /** Top-k sampling limit */
    int top_k;

    /** Repetition penalty (1.0 = no penalty) */
    float repeat_penalty;

    /** Frequency penalty */
    float frequency_penalty;

    /** Presence penalty */
    float presence_penalty;

    /** Stop sequences (NULL-terminated array of strings) */
    const char** stop_sequences;

    /** Number of stop sequences */
    int num_stop_sequences;

    /** Reserved for future use - must be NULL */
    void* reserved;
} ev_generation_params;

/**
 * @brief Get default generation parameters
 * @param params Pointer to parameters structure to fill
 */
EV_API void ev_generation_params_default(ev_generation_params* params);

/* ============================================================================
 * Single-Shot Generation
 * ========================================================================= */

/**
 * @brief Generate a complete response for given prompt
 *
 * This is a blocking call that returns the complete generated text.
 * For streaming output, use ev_generate_stream() instead.
 *
 * @param ctx Context handle
 * @param prompt Input prompt text
 * @param params Generation parameters (NULL = use defaults)
 * @param output Pointer to receive generated text (caller must free with ev_free_string)
 * @return Error code (EV_SUCCESS on success)
 */
EV_API ev_error_t ev_generate(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    char** output
);

/**
 * @brief Free string allocated by Edge Veda
 * @param str String to free
 */
EV_API void ev_free_string(char* str);

/* ============================================================================
 * Streaming Generation
 * ========================================================================= */

/**
 * @brief Opaque stream handle for streaming generation
 */
typedef struct ev_stream_impl* ev_stream;

/**
 * @brief Start streaming generation for given prompt
 *
 * Returns a stream handle that can be used with ev_stream_next()
 * to retrieve tokens as they are generated.
 *
 * @param ctx Context handle
 * @param prompt Input prompt text
 * @param params Generation parameters (NULL = use defaults)
 * @param error Optional pointer to receive error code
 * @return Stream handle on success, NULL on failure
 */
EV_API ev_stream ev_generate_stream(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    ev_error_t* error
);

/**
 * @brief Get next token from streaming generation
 *
 * This is a blocking call that waits for the next token.
 * Returns NULL when generation is complete or on error.
 *
 * @param stream Stream handle
 * @param error Optional pointer to receive error code
 * @return Next token string (caller must free with ev_free_string), or NULL when done
 */
EV_API char* ev_stream_next(ev_stream stream, ev_error_t* error);

/**
 * @brief Check if stream has more tokens available
 * @param stream Stream handle
 * @return true if more tokens available, false if ended or error
 */
EV_API bool ev_stream_has_next(ev_stream stream);

/**
 * @brief Cancel ongoing streaming generation
 * @param stream Stream handle
 */
EV_API void ev_stream_cancel(ev_stream stream);

/**
 * @brief Free stream handle and release resources
 * @param stream Stream handle to free
 */
EV_API void ev_stream_free(ev_stream stream);

/* ============================================================================
 * Memory Management
 * ========================================================================= */

/**
 * @brief Memory usage statistics
 */
typedef struct {
    /** Current memory usage in bytes */
    size_t current_bytes;

    /** Peak memory usage in bytes */
    size_t peak_bytes;

    /** Memory limit in bytes (0 = no limit) */
    size_t limit_bytes;

    /** Memory used by model in bytes */
    size_t model_bytes;

    /** Memory used by context in bytes */
    size_t context_bytes;

    /** Reserved for future use */
    size_t reserved[8];
} ev_memory_stats;

/**
 * @brief Get current memory usage statistics
 * @param ctx Context handle
 * @param stats Pointer to stats structure to fill
 * @return Error code (EV_SUCCESS on success)
 */
EV_API ev_error_t ev_get_memory_usage(ev_context ctx, ev_memory_stats* stats);

/**
 * @brief Set memory limit for context
 *
 * If auto_unload is enabled in config, the context will automatically
 * unload resources when this limit is approached.
 *
 * @param ctx Context handle
 * @param limit_bytes Memory limit in bytes (0 = no limit)
 * @return Error code (EV_SUCCESS on success)
 */
EV_API ev_error_t ev_set_memory_limit(ev_context ctx, size_t limit_bytes);

/**
 * @brief Memory pressure callback function type
 *
 * @param user_data User-provided data pointer
 * @param current_bytes Current memory usage
 * @param limit_bytes Memory limit
 */
typedef void (*ev_memory_pressure_callback)(
    void* user_data,
    size_t current_bytes,
    size_t limit_bytes
);

/**
 * @brief Register callback for memory pressure events
 *
 * The callback will be invoked when memory usage approaches the limit.
 *
 * @param ctx Context handle
 * @param callback Callback function (NULL to unregister)
 * @param user_data User data to pass to callback
 * @return Error code (EV_SUCCESS on success)
 */
EV_API ev_error_t ev_set_memory_pressure_callback(
    ev_context ctx,
    ev_memory_pressure_callback callback,
    void* user_data
);

/**
 * @brief Manually trigger garbage collection and memory cleanup
 * @param ctx Context handle
 * @return Error code (EV_SUCCESS on success)
 */
EV_API ev_error_t ev_memory_cleanup(ev_context ctx);

/* ============================================================================
 * Model Information
 * ========================================================================= */

/**
 * @brief Model metadata information
 */
typedef struct {
    /** Model name */
    const char* name;

    /** Model architecture */
    const char* architecture;

    /** Number of parameters */
    uint64_t num_parameters;

    /** Context length */
    int context_length;

    /** Embedding dimension */
    int embedding_dim;

    /** Number of layers */
    int num_layers;

    /** Reserved for future use */
    void* reserved;
} ev_model_info;

/**
 * @brief Get model metadata information
 *
 * The returned structure contains pointers to internal strings
 * and is valid until the context is freed.
 *
 * @param ctx Context handle
 * @param info Pointer to info structure to fill
 * @return Error code (EV_SUCCESS on success)
 */
EV_API ev_error_t ev_get_model_info(ev_context ctx, ev_model_info* info);

/* ============================================================================
 * Utility Functions
 * ========================================================================= */

/**
 * @brief Enable or disable verbose logging
 * @param enable true to enable, false to disable
 */
EV_API void ev_set_verbose(bool enable);

/**
 * @brief Get last error message for context
 * @param ctx Context handle
 * @return Last error message string (valid until next API call)
 */
EV_API const char* ev_get_last_error(ev_context ctx);

/**
 * @brief Reset context state (clear conversation history)
 * @param ctx Context handle
 * @return Error code (EV_SUCCESS on success)
 */
EV_API ev_error_t ev_reset(ev_context ctx);

/* ============================================================================
 * Vision API (VLM - Vision Language Model)
 * ========================================================================= */

/**
 * @brief Opaque context handle for Edge Veda vision inference engine
 *
 * Vision context is SEPARATE from text context (ev_context).
 * Create with ev_vision_init(), free with ev_vision_free().
 */
typedef struct ev_vision_context_impl* ev_vision_context;

/**
 * @brief Configuration structure for initializing vision context
 */
typedef struct {
    /** Path to VLM GGUF model file */
    const char* model_path;

    /** Path to mmproj (multimodal projector) GGUF file */
    const char* mmproj_path;

    /** Number of CPU threads (0 = auto-detect) */
    int num_threads;

    /** Token context window size (0 = auto, based on model) */
    int context_size;

    /** Batch size for processing (0 = default 512) */
    int batch_size;

    /** Memory limit in bytes (0 = no limit) */
    size_t memory_limit_bytes;

    /** GPU layers to offload (-1 = all, 0 = none) */
    int gpu_layers;

    /** Use memory mapping for model file */
    bool use_mmap;

    /** Reserved for future use - must be NULL */
    void* reserved;
} ev_vision_config;

/**
 * @brief Get default vision configuration with recommended settings
 * @param config Pointer to config structure to fill
 */
EV_API void ev_vision_config_default(ev_vision_config* config);

/**
 * @brief Initialize vision context with VLM model and mmproj
 *
 * Loads the vision language model and multimodal projector.
 * The vision context is independent from any text context.
 *
 * @param config Vision configuration (model_path and mmproj_path required)
 * @param error Optional pointer to receive error code
 * @return Vision context handle on success, NULL on failure
 */
EV_API ev_vision_context ev_vision_init(
    const ev_vision_config* config,
    ev_error_t* error
);

/**
 * @brief Describe an image using the vision model
 *
 * Takes raw RGB888 image bytes and a text prompt, returns a text description.
 * This is a blocking call that returns the complete generated text.
 *
 * @param ctx Vision context handle
 * @param image_bytes Raw pixel data in RGB888 format (width * height * 3 bytes)
 * @param width Image width in pixels
 * @param height Image height in pixels
 * @param prompt User prompt (e.g., "Describe this image")
 * @param params Generation parameters (NULL = use defaults)
 * @param output Pointer to receive generated text (caller must free with ev_free_string)
 * @return Error code (EV_SUCCESS on success)
 */
EV_API ev_error_t ev_vision_describe(
    ev_vision_context ctx,
    const unsigned char* image_bytes,
    int width,
    int height,
    const char* prompt,
    const ev_generation_params* params,
    char** output
);

/**
 * @brief Free vision context and release all resources
 * @param ctx Vision context handle to free
 */
EV_API void ev_vision_free(ev_vision_context ctx);

/**
 * @brief Check if vision context is valid and ready for inference
 * @param ctx Vision context handle
 * @return true if valid and model is loaded, false otherwise
 */
EV_API bool ev_vision_is_valid(ev_vision_context ctx);

#ifdef __cplusplus
}
#endif

#endif /* EDGE_VEDA_H */
