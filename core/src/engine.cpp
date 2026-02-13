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
#include <cmath>
#include <algorithm>
#include <string>
#include <vector>
#include <mutex>
#include <memory>
#include <atomic>

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
    ev_context ctx;                    // Parent context (shared, NOT owned)
    std::string prompt;                // Original prompt
    ev_generation_params params;       // Generation parameters
    bool ended;                        // Stream completion flag
    std::atomic<bool> cancelled{false}; // Thread-safe cancel flag

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // llama.cpp streaming state
    llama_sampler* sampler = nullptr;        // Token sampler (owned by stream)
    std::vector<llama_token> prompt_tokens;  // Tokenized prompt
    int n_cur = 0;                           // Current position in generation
    bool prompt_evaluated = false;           // Whether prompt has been processed
#endif

    // Confidence tracking
    float last_confidence = -1.0f;      // Last token's confidence (-1 = not computed)
    double confidence_sum = 0.0;         // Running sum for average
    int confidence_count = 0;            // Number of confidence measurements
    bool needs_handoff = false;          // Cloud handoff signal

    std::mutex mutex;

    ev_stream_impl(ev_context context, const char* p, const ev_generation_params* prms)
        : ctx(context)
        , prompt(p ? p : "")
        , ended(false)
        , cancelled(false) {
        if (prms) {
            // Note: grammar_str and grammar_root are borrowed pointers from the caller.
            // They must remain valid for the lifetime of the stream.
            params = *prms;
        } else {
            ev_generation_params_default(&params);
        }
    }

    ~ev_stream_impl() {
#ifdef EDGE_VEDA_LLAMA_ENABLED
        if (sampler) {
            llama_sampler_free(sampler);
            sampler = nullptr;
        }
#endif
    }

    bool check_cancelled() {
        return cancelled.load(std::memory_order_acquire);
    }

    void request_cancel() {
        cancelled.store(true, std::memory_order_release);
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
    config->flash_attn = -1; // AUTO (Metal enables automatically)
    config->kv_cache_type_k = 1; // F16 (llama.cpp default -- Dart side overrides to Q8_0)
    config->kv_cache_type_v = 1; // F16 (llama.cpp default -- Dart side overrides to Q8_0)
    config->reserved = nullptr;
}

/* ============================================================================
 * Context Management
 * ========================================================================= */

ev_context ev_init(const ev_config* config, ev_error_t* error) {
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

    // Load model (using new API: llama_model_load_from_file)
    ctx->model = llama_model_load_from_file(ctx->model_path.c_str(), model_params);
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

    // KV cache quantization (Q8_0 halves KV cache memory vs F16 default)
    if (config->kv_cache_type_k > 0) {
        ctx_params.type_k = static_cast<ggml_type>(config->kv_cache_type_k);
    }
    if (config->kv_cache_type_v > 0) {
        ctx_params.type_v = static_cast<ggml_type>(config->kv_cache_type_v);
    }

    // Flash attention (AUTO lets llama.cpp enable when backend supports it)
    if (config->flash_attn != 0) {
        ctx_params.flash_attn_type = static_cast<llama_flash_attn_type>(config->flash_attn);
    }

    // Create llama context (using new API: llama_init_from_model)
    ctx->llama_ctx = llama_init_from_model(ctx->model, ctx_params);
    if (!ctx->llama_ctx) {
        ctx->last_error = "Failed to create llama context";
        llama_model_free(ctx->model);
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
        llama_model_free(ctx->model);
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
 * @param model The llama model for tokenization (vocab extracted internally)
 * @param text The input text to tokenize
 * @param add_bos Whether to add beginning-of-sequence token
 * @return Vector of tokens
 */
static std::vector<llama_token> tokenize_prompt(
    const llama_model* model,
    const std::string& text,
    bool add_bos
) {
    // Get vocab from model (new API)
    const llama_vocab* vocab = llama_model_get_vocab(model);

    // Get max tokens needed (rough estimate: 1 token per character + BOS)
    int n_tokens = static_cast<int>(text.length()) + (add_bos ? 1 : 0);
    std::vector<llama_token> tokens(static_cast<size_t>(n_tokens));

    // Tokenize using vocab
    n_tokens = llama_tokenize(vocab, text.c_str(), static_cast<int32_t>(text.length()),
                              tokens.data(), static_cast<int32_t>(tokens.size()), add_bos, false);

    if (n_tokens < 0) {
        // Buffer was too small, resize and retry
        tokens.resize(static_cast<size_t>(-n_tokens));
        n_tokens = llama_tokenize(vocab, text.c_str(), static_cast<int32_t>(text.length()),
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
 * @param vocab  Vocabulary (needed for grammar sampler; may be nullptr if no grammar)
 * @return Configured sampler chain
 */
static llama_sampler* create_sampler(
    const ev_generation_params& params,
    const llama_vocab* vocab
) {
    llama_sampler_chain_params chain_params = llama_sampler_chain_default_params();
    llama_sampler* sampler = llama_sampler_chain_init(chain_params);

    // Add samplers in order: penalties -> top-k -> top-p -> temperature -> grammar -> dist
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

    // Add grammar sampler if grammar provided (constrains valid tokens at each step)
    if (params.grammar_str && params.grammar_str[0] != '\0' && vocab) {
        const char* root = (params.grammar_root && params.grammar_root[0] != '\0')
            ? params.grammar_root : "root";
        llama_sampler_chain_add(sampler,
            llama_sampler_init_grammar(vocab, params.grammar_str, root));
    }

    // dist sampler (always last -- performs final random selection)
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
    params->grammar_str = nullptr;
    params->grammar_root = nullptr;
    params->confidence_threshold = 0.0f;
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
    llama_memory_clear(llama_get_memory(ctx->llama_ctx), true);

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

    // Evaluate prompt in batches of n_batch
    const int n_prompt = static_cast<int>(tokens.size());
    const int n_batch = static_cast<int>(llama_n_batch(ctx->llama_ctx));

    for (int i = 0; i < n_prompt; i += n_batch) {
        const int n_eval = std::min(n_batch, n_prompt - i);
        llama_batch batch = llama_batch_get_one(tokens.data() + i, n_eval);
        if (llama_decode(ctx->llama_ctx, batch) != 0) {
            ctx->last_error = "Failed to evaluate prompt";
            return EV_ERROR_INFERENCE_FAILED;
        }
    }

    // Create sampler (pass vocab for grammar support)
    const llama_vocab* vocab = llama_model_get_vocab(ctx->model);
    llama_sampler* sampler = create_sampler(gen_params, vocab);
    if (!sampler) {
        ctx->last_error = "Failed to create sampler";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Generate tokens
    std::string result;

    for (int i = 0; i < gen_params.max_tokens; ++i) {
        // Sample next token
        llama_token new_token = llama_sampler_sample(sampler, ctx->llama_ctx, -1);

        // Check for EOS (using vocab, new API: llama_vocab_is_eog)
        if (llama_vocab_is_eog(vocab, new_token)) {
            break;
        }

        // Convert token to text (using vocab)
        char buf[256];
        int n = llama_token_to_piece(vocab, new_token, buf, sizeof(buf), 0, true);
        if (n > 0) {
            result.append(buf, static_cast<size_t>(n));
        }

        // Prepare next batch
        llama_batch next_batch = llama_batch_get_one(&new_token, 1);

        // Evaluate
        if (llama_decode(ctx->llama_ctx, next_batch) != 0) {
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

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Tokenize prompt for later evaluation
    stream->prompt_tokens = tokenize_prompt(ctx->model, prompt, true);
    if (stream->prompt_tokens.empty()) {
        delete stream;
        if (error) *error = EV_ERROR_INFERENCE_FAILED;
        return nullptr;
    }

    // Check context size
    int n_ctx = static_cast<int>(llama_n_ctx(ctx->llama_ctx));
    if (static_cast<int>(stream->prompt_tokens.size()) > n_ctx - 4) {
        delete stream;
        if (error) *error = EV_ERROR_INFERENCE_FAILED;
        return nullptr;
    }

    // Create sampler (owned by stream, pass vocab for grammar support)
    stream->sampler = create_sampler(stream->params, llama_model_get_vocab(ctx->model));
    if (!stream->sampler) {
        delete stream;
        if (error) *error = EV_ERROR_INFERENCE_FAILED;
        return nullptr;
    }
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

    // Check cancellation FIRST (before any work)
    if (stream->check_cancelled()) {
        stream->ended = true;
        if (error) *error = EV_ERROR_STREAM_ENDED;
        return nullptr;
    }

    if (stream->ended) {
        if (error) *error = EV_ERROR_STREAM_ENDED;
        return nullptr;
    }

#ifdef EDGE_VEDA_LLAMA_ENABLED
    ev_context ctx = stream->ctx;

    // Lock context for thread safety (context shared across streams)
    std::lock_guard<std::mutex> ctx_lock(ctx->mutex);

    // First call: evaluate prompt and clear KV cache
    if (!stream->prompt_evaluated) {
        // Clear KV cache for fresh generation
        llama_memory_clear(llama_get_memory(ctx->llama_ctx), true);

        // Evaluate prompt tokens in batches of n_batch
        const int n_prompt = static_cast<int>(stream->prompt_tokens.size());
        const int n_batch = static_cast<int>(llama_n_batch(ctx->llama_ctx));

        for (int i = 0; i < n_prompt; i += n_batch) {
            const int n_eval = std::min(n_batch, n_prompt - i);
            llama_batch batch = llama_batch_get_one(
                stream->prompt_tokens.data() + i, n_eval);
            if (llama_decode(ctx->llama_ctx, batch) != 0) {
                stream->ended = true;
                if (error) *error = EV_ERROR_INFERENCE_FAILED;
                return nullptr;
            }
        }

        stream->n_cur = n_prompt;
        stream->prompt_evaluated = true;
    }

    // Check max tokens limit
    int generated_count = stream->n_cur - static_cast<int>(stream->prompt_tokens.size());
    if (generated_count >= stream->params.max_tokens) {
        stream->ended = true;
        if (error) *error = EV_SUCCESS;  // Natural end, not an error
        return nullptr;
    }

    // Check cancellation again before expensive sampling
    if (stream->check_cancelled()) {
        stream->ended = true;
        if (error) *error = EV_ERROR_STREAM_ENDED;
        return nullptr;
    }

    // Sample next token
    llama_token new_token = llama_sampler_sample(stream->sampler, ctx->llama_ctx, -1);

    // Check for EOS
    const llama_vocab* vocab = llama_model_get_vocab(ctx->model);
    if (llama_vocab_is_eog(vocab, new_token)) {
        stream->ended = true;
        if (error) *error = EV_SUCCESS;  // Natural end
        return nullptr;
    }

    // Compute confidence score (only when threshold > 0)
    if (stream->params.confidence_threshold > 0.0f) {
        const float* logits = llama_get_logits_ith(ctx->llama_ctx, -1);
        const llama_vocab* vocab_for_conf = llama_model_get_vocab(ctx->model);
        int n_vocab = llama_vocab_n_tokens(vocab_for_conf);

        // Softmax with numerical stability
        float max_val = -1e30f;
        for (int i = 0; i < n_vocab; i++) {
            if (logits[i] > max_val) max_val = logits[i];
        }

        double sum_exp = 0.0;
        for (int i = 0; i < n_vocab; i++) {
            sum_exp += exp((double)(logits[i] - max_val));
        }

        // Shannon entropy: H = -sum(p * log(p))
        double entropy = 0.0;
        for (int i = 0; i < n_vocab; i++) {
            double p = exp((double)(logits[i] - max_val)) / sum_exp;
            if (p > 1e-10) entropy -= p * log(p);
        }

        // Normalize to [0, 1] and invert: 1.0 = certain, 0.0 = uniform
        double max_entropy = log((double)n_vocab);
        stream->last_confidence = (float)(1.0 - entropy / max_entropy);

        // Update running average
        stream->confidence_sum += stream->last_confidence;
        stream->confidence_count++;
        float avg = (float)(stream->confidence_sum / stream->confidence_count);

        // Check handoff threshold
        if (avg < stream->params.confidence_threshold && stream->confidence_count >= 3) {
            stream->needs_handoff = true;
        }
    }

    // Convert token to text
    char buf[256];
    int n = llama_token_to_piece(vocab, new_token, buf, sizeof(buf), 0, true);
    if (n <= 0) {
        // Empty token (can happen with special tokens), continue
        stream->n_cur++;
        if (error) *error = EV_SUCCESS;

        // Decode the empty token to maintain KV cache consistency
        llama_batch batch = llama_batch_get_one(&new_token, 1);
        llama_decode(ctx->llama_ctx, batch);

        // Return empty string (caller should continue calling)
        char* result = static_cast<char*>(std::malloc(1));
        if (result) result[0] = '\0';
        return result;
    }

    // Decode next token to update KV cache
    llama_batch batch = llama_batch_get_one(&new_token, 1);
    if (llama_decode(ctx->llama_ctx, batch) != 0) {
        stream->ended = true;
        if (error) *error = EV_ERROR_INFERENCE_FAILED;
        return nullptr;
    }

    stream->n_cur++;

    // Allocate and return token string
    char* result = static_cast<char*>(std::malloc(static_cast<size_t>(n) + 1));
    if (!result) {
        if (error) *error = EV_ERROR_OUT_OF_MEMORY;
        return nullptr;
    }
    std::memcpy(result, buf, static_cast<size_t>(n));
    result[n] = '\0';

    if (error) *error = EV_SUCCESS;
    return result;
#else
    stream->ended = true;
    if (error) *error = EV_ERROR_NOT_IMPLEMENTED;
    return nullptr;
#endif
}

bool ev_stream_has_next(ev_stream stream) {
    if (!stream) return false;
    std::lock_guard<std::mutex> lock(stream->mutex);
    return !stream->ended && !stream->check_cancelled();
}

void ev_stream_cancel(ev_stream stream) {
    if (!stream) return;
    // Use atomic operation - no mutex needed for cancel request
    stream->request_cancel();
}

void ev_stream_free(ev_stream stream) {
    if (!stream) return;
    // Destructor handles sampler cleanup
    delete stream;
}

/* ============================================================================
 * Streaming Token Info (confidence scoring)
 * ========================================================================= */

ev_error_t ev_stream_get_token_info(ev_stream stream, ev_stream_token_info* info) {
    if (!stream || !info) return EV_ERROR_INVALID_PARAM;

    std::lock_guard<std::mutex> lock(stream->mutex);

    info->confidence = stream->last_confidence;
    info->avg_confidence = stream->confidence_count > 0
        ? (float)(stream->confidence_sum / stream->confidence_count)
        : -1.0f;
    info->needs_cloud_handoff = stream->needs_handoff;
    info->token_index = stream->confidence_count;

    return EV_SUCCESS;
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
        llama_memory_clear(llama_get_memory(ctx->llama_ctx), true);
    }
#endif

    // Trigger platform memory cleanup
    memory_guard_cleanup();

    return EV_SUCCESS;
}

/* ============================================================================
 * Embeddings API
 * ========================================================================= */

#ifdef EDGE_VEDA_LLAMA_ENABLED
ev_error_t ev_embed(
    ev_context ctx,
    const char* text,
    ev_embed_result* result
) {
    // Validate parameters
    if (!ctx || !text || !result) {
        return EV_ERROR_INVALID_PARAM;
    }

    if (!ctx->model) {
        return EV_ERROR_CONTEXT_INVALID;
    }

    // Zero-initialize result
    std::memset(result, 0, sizeof(ev_embed_result));

    std::lock_guard<std::mutex> lock(ctx->mutex);

    // Create a SEPARATE embedding context
    llama_context_params emb_params = llama_context_default_params();
    emb_params.embeddings = true;
    emb_params.n_ctx = 512;
    emb_params.n_batch = 512;
    emb_params.n_threads = ctx->config.num_threads > 0
        ? static_cast<uint32_t>(ctx->config.num_threads) : 4;
    emb_params.n_threads_batch = emb_params.n_threads;
    emb_params.pooling_type = LLAMA_POOLING_TYPE_MEAN;

    llama_context* emb_ctx = llama_init_from_model(ctx->model, emb_params);
    if (!emb_ctx) {
        ctx->last_error = "Failed to create embedding context";
        return EV_ERROR_BACKEND_INIT_FAILED;
    }

    // Enable embedding mode and non-causal attention for bidirectional encoding
    llama_set_embeddings(emb_ctx, true);
    llama_set_causal_attn(emb_ctx, false);

    // Clear KV cache
    llama_memory_clear(llama_get_memory(emb_ctx), true);

    // Tokenize input text
    std::vector<llama_token> tokens = tokenize_prompt(ctx->model, text, true);
    if (tokens.empty()) {
        ctx->last_error = "Failed to tokenize text for embedding";
        llama_free(emb_ctx);
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Create batch and decode
    llama_batch batch = llama_batch_get_one(tokens.data(), static_cast<int32_t>(tokens.size()));
    if (llama_decode(emb_ctx, batch) != 0) {
        ctx->last_error = "Failed to decode for embedding";
        llama_free(emb_ctx);
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Get pooled embeddings
    const float* emb = llama_get_embeddings_seq(emb_ctx, 0);
    if (!emb) {
        // Fallback: try last token embeddings
        emb = llama_get_embeddings_ith(emb_ctx, -1);
    }
    if (!emb) {
        ctx->last_error = "Failed to retrieve embeddings";
        llama_free(emb_ctx);
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Get embedding dimension
    int n_embd = llama_model_n_embd(ctx->model);

    // Allocate result buffer
    result->embeddings = (float*)malloc(sizeof(float) * n_embd);
    if (!result->embeddings) {
        llama_free(emb_ctx);
        return EV_ERROR_OUT_OF_MEMORY;
    }

    // L2-normalize into result buffer
    double sum_sq = 0.0;
    for (int i = 0; i < n_embd; i++) {
        sum_sq += (double)emb[i] * (double)emb[i];
    }
    float norm = (sum_sq > 0.0) ? (float)(1.0 / sqrt(sum_sq)) : 0.0f;
    for (int i = 0; i < n_embd; i++) {
        result->embeddings[i] = emb[i] * norm;
    }

    result->dimensions = n_embd;
    result->token_count = static_cast<int>(tokens.size());

    // Free embedding context
    llama_free(emb_ctx);

    return EV_SUCCESS;
}
#else
ev_error_t ev_embed(
    ev_context ctx,
    const char* text,
    ev_embed_result* result
) {
    (void)ctx;
    (void)text;
    if (result) std::memset(result, 0, sizeof(ev_embed_result));
    return EV_ERROR_NOT_IMPLEMENTED;
}
#endif

void ev_free_embeddings(ev_embed_result* result) {
    if (result && result->embeddings) {
        free(result->embeddings);
        result->embeddings = nullptr;
        result->dimensions = 0;
        result->token_count = 0;
    }
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

    // Context and embedding info (using new API names)
    info->context_length = static_cast<int>(llama_n_ctx(ctx->llama_ctx));
    info->embedding_dim = static_cast<int>(llama_model_n_embd(ctx->model));
    info->num_layers = static_cast<int>(llama_model_n_layer(ctx->model));

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
    llama_memory_clear(llama_get_memory(ctx->llama_ctx), true);
    return EV_SUCCESS;
#else
    return EV_ERROR_NOT_IMPLEMENTED;
#endif
}
