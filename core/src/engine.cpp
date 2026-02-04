/**
 * @file engine.cpp
 * @brief Edge Veda SDK - Core Engine Implementation
 *
 * This file implements the public C API defined in edge_veda.h
 * using llama.cpp for on-device LLM inference.
 */

#include "edge_veda.h"
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <mutex>
#include <memory>

#ifdef EDGE_VEDA_LLAMA_ENABLED
#include "llama.h"
#include "ggml.h"
#endif

// Memory guard function declarations (defined in memory_guard.cpp)
extern "C" {
    void memory_guard_set_limit(size_t limit_bytes);
    size_t memory_guard_get_limit();
    size_t memory_guard_get_current_usage();
    size_t memory_guard_get_peak_usage();
    bool memory_guard_is_under_pressure();
    void memory_guard_cleanup();
    void memory_guard_reset_stats();
    void memory_guard_set_callback(void (*callback)(void*, size_t, size_t), void* user_data);
}

/* ============================================================================
 * Internal Structures
 * ========================================================================= */

struct ev_context_impl {
    // Configuration
    ev_config config;

    // Backend information
    ev_backend_t active_backend;

    // Model state
    bool model_loaded;
    std::string model_path;

    // Memory management
    size_t memory_limit;
    bool auto_unload;
    ev_memory_pressure_callback memory_callback;
    void* memory_callback_data;

    // Statistics
    size_t peak_memory_bytes;
    size_t current_memory_bytes;

    // Error tracking
    std::string last_error;

    // Thread safety
    std::mutex mutex;

    // llama.cpp handles
#ifdef EDGE_VEDA_LLAMA_ENABLED
    llama_model* model = nullptr;
    llama_context* llama_ctx = nullptr;
    llama_sampler* sampler = nullptr;
#endif

    // Constructor
    ev_context_impl()
        : active_backend(EV_BACKEND_AUTO)
        , model_loaded(false)
        , memory_limit(0)
        , auto_unload(false)
        , memory_callback(nullptr)
        , memory_callback_data(nullptr)
        , peak_memory_bytes(0)
        , current_memory_bytes(0) {
    }

    ~ev_context_impl() = default;
};

struct ev_stream_impl {
    ev_context ctx;
    std::string prompt;
    ev_generation_params params;
    bool ended;
    std::mutex mutex;

    // TODO: Add llama.cpp streaming state
    // std::vector<llama_token> tokens;
    // size_t current_token_idx;

    ev_stream_impl(ev_context context, const char* p, const ev_generation_params* prms)
        : ctx(context)
        , prompt(p ? p : "")
        , ended(false) {
        if (prms) {
            params = *prms;
        } else {
            ev_generation_params_default(&params);
        }
    }
};

/* ============================================================================
 * Version Information
 * ========================================================================= */

const char* ev_version(void) {
    return "1.0.0";
}

/* ============================================================================
 * Error Handling
 * ========================================================================= */

const char* ev_error_string(ev_error_t error) {
    switch (error) {
        case EV_SUCCESS: return "Success";
        case EV_ERROR_INVALID_PARAM: return "Invalid parameter";
        case EV_ERROR_OUT_OF_MEMORY: return "Out of memory";
        case EV_ERROR_MODEL_LOAD_FAILED: return "Failed to load model";
        case EV_ERROR_BACKEND_INIT_FAILED: return "Failed to initialize backend";
        case EV_ERROR_INFERENCE_FAILED: return "Inference failed";
        case EV_ERROR_CONTEXT_INVALID: return "Invalid context";
        case EV_ERROR_STREAM_ENDED: return "Stream ended";
        case EV_ERROR_NOT_IMPLEMENTED: return "Not implemented";
        case EV_ERROR_MEMORY_LIMIT_EXCEEDED: return "Memory limit exceeded";
        case EV_ERROR_UNSUPPORTED_BACKEND: return "Backend not supported";
        default: return "Unknown error";
    }
}

/* ============================================================================
 * Backend Detection
 * ========================================================================= */

ev_backend_t ev_detect_backend(void) {
#if defined(__APPLE__)
    #include "TargetConditionals.h"
    #if TARGET_OS_IOS || TARGET_OS_OSX
        #ifdef EDGE_VEDA_METAL_ENABLED
            return EV_BACKEND_METAL;
        #endif
    #endif
#elif defined(__ANDROID__)
    #ifdef EDGE_VEDA_VULKAN_ENABLED
        return EV_BACKEND_VULKAN;
    #endif
#endif

#ifdef EDGE_VEDA_CPU_ENABLED
    return EV_BACKEND_CPU;
#else
    return EV_BACKEND_AUTO;
#endif
}

bool ev_is_backend_available(ev_backend_t backend) {
    switch (backend) {
        case EV_BACKEND_METAL:
#ifdef EDGE_VEDA_METAL_ENABLED
            return true;
#else
            return false;
#endif

        case EV_BACKEND_VULKAN:
#ifdef EDGE_VEDA_VULKAN_ENABLED
            return true;
#else
            return false;
#endif

        case EV_BACKEND_CPU:
#ifdef EDGE_VEDA_CPU_ENABLED
            return true;
#else
            return false;
#endif

        case EV_BACKEND_AUTO:
            return true;

        default:
            return false;
    }
}

const char* ev_backend_name(ev_backend_t backend) {
    switch (backend) {
        case EV_BACKEND_AUTO: return "Auto";
        case EV_BACKEND_METAL: return "Metal";
        case EV_BACKEND_VULKAN: return "Vulkan";
        case EV_BACKEND_CPU: return "CPU";
        default: return "Unknown";
    }
}

/* ============================================================================
 * Configuration
 * ========================================================================= */

void ev_config_default(ev_config* config) {
    if (!config) return;

    std::memset(config, 0, sizeof(ev_config));
    config->model_path = nullptr;
    config->backend = EV_BACKEND_AUTO;
    config->num_threads = 0; // Auto-detect
    config->context_size = 2048;
    config->batch_size = 512;
    config->memory_limit_bytes = 0; // No limit
    config->auto_unload_on_memory_pressure = true;
    config->gpu_layers = -1; // All layers
    config->use_mmap = true;
    config->use_mlock = false;
    config->seed = -1; // Random
    config->reserved = nullptr;
}

/* ============================================================================
 * Context Management
 * ========================================================================= */

ev_context ev_init(const ev_config* config, ev_error_t* error) {
    ev_error_t err = EV_SUCCESS;

    if (!config || !config->model_path) {
        if (error) *error = EV_ERROR_INVALID_PARAM;
        return nullptr;
    }

    // Allocate context
    ev_context ctx = new (std::nothrow) ev_context_impl();
    if (!ctx) {
        if (error) *error = EV_ERROR_OUT_OF_MEMORY;
        return nullptr;
    }

    ctx->config = *config;
    ctx->model_path = config->model_path;
    ctx->memory_limit = config->memory_limit_bytes;
    ctx->auto_unload = config->auto_unload_on_memory_pressure;

    // Detect backend
    ctx->active_backend = (config->backend == EV_BACKEND_AUTO)
        ? ev_detect_backend()
        : config->backend;

    if (!ev_is_backend_available(ctx->active_backend)) {
        ctx->last_error = "Backend not available";
        delete ctx;
        if (error) *error = EV_ERROR_UNSUPPORTED_BACKEND;
        return nullptr;
    }

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Initialize llama.cpp backend
    llama_backend_init();

    // Configure model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = config->gpu_layers;
    model_params.use_mmap = config->use_mmap;
    model_params.use_mlock = config->use_mlock;

    // Load model
    ctx->model = llama_load_model_from_file(ctx->model_path.c_str(), model_params);
    if (!ctx->model) {
        ctx->last_error = "Failed to load model from: " + ctx->model_path;
        llama_backend_free();
        delete ctx;
        if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
        return nullptr;
    }

    // Configure context parameters
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = config->context_size > 0 ? static_cast<uint32_t>(config->context_size) : 2048;
    ctx_params.n_batch = config->batch_size > 0 ? static_cast<uint32_t>(config->batch_size) : 512;
    ctx_params.n_threads = config->num_threads > 0 ? static_cast<uint32_t>(config->num_threads) : 4;
    ctx_params.n_threads_batch = ctx_params.n_threads;

    // Create llama context
    ctx->llama_ctx = llama_new_context_with_model(ctx->model, ctx_params);
    if (!ctx->llama_ctx) {
        ctx->last_error = "Failed to create llama context";
        llama_free_model(ctx->model);
        llama_backend_free();
        delete ctx;
        if (error) *error = EV_ERROR_BACKEND_INIT_FAILED;
        return nullptr;
    }

    ctx->model_loaded = true;

    // Set up memory monitoring
    if (ctx->memory_limit > 0) {
        memory_guard_set_limit(static_cast<uint64_t>(ctx->memory_limit));
    }

    if (error) *error = EV_SUCCESS;
    return ctx;
#else
    ctx->last_error = "llama.cpp not compiled - library built without LLM support";
    delete ctx;
    if (error) *error = EV_ERROR_NOT_IMPLEMENTED;
    return nullptr;
#endif
}

void ev_free(ev_context ctx) {
    if (!ctx) return;

    std::lock_guard<std::mutex> lock(ctx->mutex);

#ifdef EDGE_VEDA_LLAMA_ENABLED
    if (ctx->sampler) {
        llama_sampler_free(ctx->sampler);
        ctx->sampler = nullptr;
    }
    if (ctx->llama_ctx) {
        llama_free(ctx->llama_ctx);
        ctx->llama_ctx = nullptr;
    }
    if (ctx->model) {
        llama_free_model(ctx->model);
        ctx->model = nullptr;
    }
    llama_backend_free();
#endif

    delete ctx;
}

bool ev_is_valid(ev_context ctx) {
    return ctx != nullptr && ctx->model_loaded;
}

/* ============================================================================
 * Internal Helper Functions
 * ========================================================================= */

#ifdef EDGE_VEDA_LLAMA_ENABLED
/**
 * Tokenize a text prompt into llama tokens
 * @param model The llama model for tokenization
 * @param text The input text to tokenize
 * @param add_bos Whether to add beginning-of-sequence token
 * @return Vector of tokens
 */
static std::vector<llama_token> tokenize_prompt(
    const llama_model* model,
    const std::string& text,
    bool add_bos
) {
    // Get max tokens needed (rough estimate: 1 token per character + BOS)
    int n_tokens = static_cast<int>(text.length()) + (add_bos ? 1 : 0);
    std::vector<llama_token> tokens(static_cast<size_t>(n_tokens));

    // Tokenize
    n_tokens = llama_tokenize(model, text.c_str(), static_cast<int32_t>(text.length()),
                              tokens.data(), static_cast<int32_t>(tokens.size()), add_bos, false);

    if (n_tokens < 0) {
        // Buffer was too small, resize and retry
        tokens.resize(static_cast<size_t>(-n_tokens));
        n_tokens = llama_tokenize(model, text.c_str(), static_cast<int32_t>(text.length()),
                                  tokens.data(), static_cast<int32_t>(tokens.size()), add_bos, false);
    }

    if (n_tokens >= 0) {
        tokens.resize(static_cast<size_t>(n_tokens));
    } else {
        tokens.clear();
    }
    return tokens;
}

/**
 * Create a sampler chain with the specified generation parameters
 * @param params Generation parameters
 * @return Configured sampler chain
 */
static llama_sampler* create_sampler(const ev_generation_params& params) {
    llama_sampler_chain_params chain_params = llama_sampler_chain_default_params();
    llama_sampler* sampler = llama_sampler_chain_init(chain_params);

    // Add samplers in order: penalties -> top-k -> top-p -> temperature -> dist
    llama_sampler_chain_add(sampler,
        llama_sampler_init_penalties(
            64,                        // penalty_last_n
            params.repeat_penalty,     // repeat_penalty
            params.frequency_penalty,  // frequency_penalty
            params.presence_penalty    // presence_penalty
        ));

    if (params.top_k > 0) {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(params.top_k));
    }

    if (params.top_p < 1.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params.top_p, 1));
    }

    if (params.temperature > 0.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(params.temperature));
    }

    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    return sampler;
}
#endif

/* ============================================================================
 * Generation Parameters
 * ========================================================================= */

void ev_generation_params_default(ev_generation_params* params) {
    if (!params) return;

    std::memset(params, 0, sizeof(ev_generation_params));
    params->max_tokens = 512;
    params->temperature = 0.8f;
    params->top_p = 0.95f;
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

ev_error_t ev_generate(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    char** output
) {
    if (!ctx || !prompt || !output) {
        return EV_ERROR_INVALID_PARAM;
    }

    if (!ev_is_valid(ctx)) {
        return EV_ERROR_CONTEXT_INVALID;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);

    ev_generation_params gen_params;
    if (params) {
        gen_params = *params;
    } else {
        ev_generation_params_default(&gen_params);
    }

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Clear KV cache for fresh generation
    llama_kv_cache_clear(ctx->llama_ctx);

    // Tokenize prompt
    std::vector<llama_token> tokens = tokenize_prompt(ctx->model, prompt, true);
    if (tokens.empty()) {
        ctx->last_error = "Failed to tokenize prompt";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Check context size
    int n_ctx = static_cast<int>(llama_n_ctx(ctx->llama_ctx));
    if (static_cast<int>(tokens.size()) > n_ctx - 4) {
        ctx->last_error = "Prompt too long for context size";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Create batch for prompt processing
    llama_batch batch = llama_batch_get_one(tokens.data(), static_cast<int32_t>(tokens.size()));

    // Evaluate prompt
    if (llama_decode(ctx->llama_ctx, batch) != 0) {
        ctx->last_error = "Failed to evaluate prompt";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Create sampler
    llama_sampler* sampler = create_sampler(gen_params);
    if (!sampler) {
        ctx->last_error = "Failed to create sampler";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Generate tokens
    std::string result;

    for (int i = 0; i < gen_params.max_tokens; ++i) {
        // Sample next token
        llama_token new_token = llama_sampler_sample(sampler, ctx->llama_ctx, -1);

        // Check for EOS
        if (llama_token_is_eog(ctx->model, new_token)) {
            break;
        }

        // Convert token to text
        char buf[256];
        int n = llama_token_to_piece(ctx->model, new_token, buf, sizeof(buf), 0, true);
        if (n > 0) {
            result.append(buf, static_cast<size_t>(n));
        }

        // Prepare next batch
        batch = llama_batch_get_one(&new_token, 1);

        // Evaluate
        if (llama_decode(ctx->llama_ctx, batch) != 0) {
            llama_sampler_free(sampler);
            ctx->last_error = "Failed during generation";
            return EV_ERROR_INFERENCE_FAILED;
        }
    }

    llama_sampler_free(sampler);

    // Allocate output string
    *output = static_cast<char*>(std::malloc(result.size() + 1));
    if (!*output) {
        return EV_ERROR_OUT_OF_MEMORY;
    }
    std::memcpy(*output, result.c_str(), result.size() + 1);

    return EV_SUCCESS;
#else
    ctx->last_error = "llama.cpp not compiled";
    return EV_ERROR_NOT_IMPLEMENTED;
#endif
}

void ev_free_string(char* str) {
    if (str) {
        std::free(str);
    }
}

/* ============================================================================
 * Streaming Generation
 * ========================================================================= */

ev_stream ev_generate_stream(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    ev_error_t* error
) {
    if (!ctx || !prompt) {
        if (error) *error = EV_ERROR_INVALID_PARAM;
        return nullptr;
    }

    if (!ev_is_valid(ctx)) {
        if (error) *error = EV_ERROR_CONTEXT_INVALID;
        return nullptr;
    }

    ev_stream stream = new (std::nothrow) ev_stream_impl(ctx, prompt, params);
    if (!stream) {
        if (error) *error = EV_ERROR_OUT_OF_MEMORY;
        return nullptr;
    }

    // TODO: Initialize streaming with llama.cpp
#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Tokenize and prepare for streaming
    // stream->tokens = llama_tokenize(ctx->ctx, prompt, true);
    // stream->current_token_idx = 0;
#endif

    if (error) *error = EV_SUCCESS;
    return stream;
}

char* ev_stream_next(ev_stream stream, ev_error_t* error) {
    if (!stream) {
        if (error) *error = EV_ERROR_INVALID_PARAM;
        return nullptr;
    }

    std::lock_guard<std::mutex> lock(stream->mutex);

    if (stream->ended) {
        if (error) *error = EV_ERROR_STREAM_ENDED;
        return nullptr;
    }

    // TODO: Generate next token with llama.cpp
#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Generate and return next token
    // ...

    if (error) *error = EV_SUCCESS;
    // return token_string;
#endif

    stream->ended = true;
    if (error) *error = EV_ERROR_NOT_IMPLEMENTED;
    return nullptr;
}

bool ev_stream_has_next(ev_stream stream) {
    if (!stream) return false;
    std::lock_guard<std::mutex> lock(stream->mutex);
    return !stream->ended;
}

void ev_stream_cancel(ev_stream stream) {
    if (!stream) return;
    std::lock_guard<std::mutex> lock(stream->mutex);
    stream->ended = true;
}

void ev_stream_free(ev_stream stream) {
    if (!stream) return;
    delete stream;
}

/* ============================================================================
 * Memory Management
 * ========================================================================= */

ev_error_t ev_get_memory_usage(ev_context ctx, ev_memory_stats* stats) {
    if (!ctx || !stats) {
        return EV_ERROR_INVALID_PARAM;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    std::memset(stats, 0, sizeof(ev_memory_stats));

    // Get platform memory from memory guard
    stats->current_bytes = static_cast<size_t>(memory_guard_get_current_usage());
    stats->peak_bytes = ctx->peak_memory_bytes;
    stats->limit_bytes = ctx->memory_limit;

#ifdef EDGE_VEDA_LLAMA_ENABLED
    if (ctx->model) {
        // Get model size (approximate)
        stats->model_bytes = llama_model_size(ctx->model);
    }
    if (ctx->llama_ctx) {
        // Context memory usage
        stats->context_bytes = llama_state_get_size(ctx->llama_ctx);
    }
#endif

    // Update peak
    if (stats->current_bytes > ctx->peak_memory_bytes) {
        ctx->peak_memory_bytes = stats->current_bytes;
    }

    return EV_SUCCESS;
}

ev_error_t ev_set_memory_limit(ev_context ctx, size_t limit_bytes) {
    if (!ctx) {
        return EV_ERROR_INVALID_PARAM;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    ctx->memory_limit = limit_bytes;
    memory_guard_set_limit(limit_bytes);

    return EV_SUCCESS;
}

ev_error_t ev_set_memory_pressure_callback(
    ev_context ctx,
    ev_memory_pressure_callback callback,
    void* user_data
) {
    if (!ctx) {
        return EV_ERROR_INVALID_PARAM;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    ctx->memory_callback = callback;
    ctx->memory_callback_data = user_data;

    // Set up memory guard callback wrapper
    if (callback) {
        auto wrapper = [](void* data, size_t current, size_t limit) {
            ev_context ctx = static_cast<ev_context>(data);
            if (ctx->memory_callback) {
                ctx->memory_callback(ctx->memory_callback_data, current, limit);
            }
        };
        memory_guard_set_callback(wrapper, ctx);
    } else {
        memory_guard_set_callback(nullptr, nullptr);
    }

    return EV_SUCCESS;
}

ev_error_t ev_memory_cleanup(ev_context ctx) {
    if (!ctx) {
        return EV_ERROR_INVALID_PARAM;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Clear KV cache to free memory
    if (ctx->llama_ctx) {
        llama_kv_cache_clear(ctx->llama_ctx);
    }
#endif

    // Trigger platform memory cleanup
    memory_guard_cleanup();

    return EV_SUCCESS;
}

/* ============================================================================
 * Model Information
 * ========================================================================= */

// Static buffer for model description (used by ev_get_model_info)
static char g_model_desc[256] = {0};

ev_error_t ev_get_model_info(ev_context ctx, ev_model_info* info) {
    if (!ctx || !info) {
        return EV_ERROR_INVALID_PARAM;
    }

    if (!ev_is_valid(ctx)) {
        return EV_ERROR_CONTEXT_INVALID;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    std::memset(info, 0, sizeof(ev_model_info));

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Model description
    llama_model_desc(ctx->model, g_model_desc, sizeof(g_model_desc));
    info->name = g_model_desc;

    // Architecture (most GGUF models are llama-based)
    info->architecture = "llama";

    // Parameters
    info->num_parameters = llama_model_n_params(ctx->model);

    // Context and embedding info
    info->context_length = static_cast<int>(llama_n_ctx(ctx->llama_ctx));
    info->embedding_dim = static_cast<int>(llama_n_embd(ctx->model));
    info->num_layers = static_cast<int>(llama_n_layer(ctx->model));

    return EV_SUCCESS;
#else
    return EV_ERROR_NOT_IMPLEMENTED;
#endif
}

/* ============================================================================
 * Utility Functions
 * ========================================================================= */

static bool g_verbose = false;

void ev_set_verbose(bool enable) {
    g_verbose = enable;

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // llama.cpp uses log callback, set it based on verbosity
    if (enable) {
        llama_log_set([](enum ggml_log_level level, const char* text, void* /* user_data */) {
            fprintf(stderr, "[llama] %s", text);
            (void)level;
        }, nullptr);
    } else {
        llama_log_set([](enum ggml_log_level level, const char* text, void* /* user_data */) {
            // Suppress all but errors
            if (level == GGML_LOG_LEVEL_ERROR) {
                fprintf(stderr, "[llama] %s", text);
            }
        }, nullptr);
    }
#endif
}

const char* ev_get_last_error(ev_context ctx) {
    if (!ctx) {
        return "Invalid context";
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    return ctx->last_error.c_str();
}

ev_error_t ev_reset(ev_context ctx) {
    if (!ctx) {
        return EV_ERROR_INVALID_PARAM;
    }

    if (!ev_is_valid(ctx)) {
        return EV_ERROR_CONTEXT_INVALID;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);

#ifdef EDGE_VEDA_LLAMA_ENABLED
    llama_kv_cache_clear(ctx->llama_ctx);
    return EV_SUCCESS;
#else
    return EV_ERROR_NOT_IMPLEMENTED;
#endif
}
