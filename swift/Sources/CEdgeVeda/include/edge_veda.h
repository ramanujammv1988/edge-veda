#ifndef EDGE_VEDA_H
#define EDGE_VEDA_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

// MARK: - Types

/// Opaque handle to a loaded model
typedef void* edge_veda_model_t;

// MARK: - Configuration

/// Model configuration
typedef struct {
    int32_t backend;           // 0=CPU, 1=Metal, 2=Auto
    int32_t threads;           // Number of threads (0=auto)
    int32_t context_size;      // Context window size
    int32_t gpu_layers;        // GPU layers to offload (-1=all, 0=none)
    int32_t batch_size;        // Batch size for processing
    bool use_mmap;             // Use memory mapping
    bool use_mlock;            // Lock memory to prevent swapping
    bool verbose;              // Verbose logging
} edge_veda_config;

// MARK: - Generation Parameters

/// Text generation parameters
typedef struct {
    int32_t max_tokens;                    // Maximum tokens to generate
    float temperature;                     // Sampling temperature
    float top_p;                          // Nucleus sampling threshold
    int32_t top_k;                        // Top-K sampling limit
    float repeat_penalty;                 // Repetition penalty
    char** stop_sequences;                // Array of stop sequences
    int32_t stop_sequences_count;         // Number of stop sequences
} edge_veda_generate_params;

// MARK: - Callbacks

/// Streaming token callback
/// @param token The generated token text (null-terminated)
/// @param token_id The token ID
/// @param user_data User-provided context pointer
typedef void (*edge_veda_stream_callback)(
    const char* token,
    int32_t token_id,
    void* user_data
);

// MARK: - Model Management

/// Load a model from disk
/// @param path Path to GGUF model file
/// @param config Model configuration
/// @param error Buffer to store error message (512 bytes minimum)
/// @return Model handle, or NULL on failure
edge_veda_model_t edge_veda_load_model(
    const char* path,
    const edge_veda_config* config,
    char* error
);

/// Free a loaded model
/// @param model Model handle
void edge_veda_free_model(edge_veda_model_t model);

// MARK: - Text Generation

/// Generate text synchronously
/// @param model Model handle
/// @param prompt Input prompt text
/// @param params Generation parameters
/// @param error Buffer to store error message (512 bytes minimum)
/// @return Generated text (must be freed with edge_veda_free_string), or NULL on failure
char* edge_veda_generate(
    edge_veda_model_t model,
    const char* prompt,
    const edge_veda_generate_params* params,
    char* error
);

/// Generate text with streaming callback
/// @param model Model handle
/// @param prompt Input prompt text
/// @param params Generation parameters
/// @param callback Token callback function
/// @param user_data User context pointer passed to callback
/// @param error Buffer to store error message (512 bytes minimum)
/// @return 0 on success, non-zero on failure
int32_t edge_veda_generate_stream(
    edge_veda_model_t model,
    const char* prompt,
    const edge_veda_generate_params* params,
    edge_veda_stream_callback callback,
    void* user_data,
    char* error
);

// MARK: - Model Information

/// Get current memory usage in bytes
/// @param model Model handle
/// @return Memory usage in bytes
uint64_t edge_veda_get_memory_usage(edge_veda_model_t model);

/// Get number of metadata entries
/// @param model Model handle
/// @return Number of metadata entries
int32_t edge_veda_get_metadata_count(edge_veda_model_t model);

/// Get metadata entry by index
/// @param model Model handle
/// @param index Entry index
/// @param key Buffer for key (256 bytes minimum)
/// @param value Buffer for value (1024 bytes minimum)
/// @return 0 on success, non-zero on failure
int32_t edge_veda_get_metadata_entry(
    edge_veda_model_t model,
    int32_t index,
    char* key,
    char* value
);

// MARK: - Context Management

/// Reset conversation context
/// @param model Model handle
void edge_veda_reset_context(edge_veda_model_t model);

// MARK: - Memory Management

/// Free string allocated by library
/// @param str String to free
void edge_veda_free_string(char* str);

#ifdef __cplusplus
}
#endif

#endif // EDGE_VEDA_H
