/**
 * @file vision_engine.cpp
 * @brief Edge Veda SDK - Vision Engine Implementation
 *
 * This file implements the ev_vision_* public C API defined in edge_veda.h
 * using libmtmd from llama.cpp b7952 for multimodal (image-to-text) inference.
 *
 * Vision context is SEPARATE from the text context in engine.cpp.
 * Image bytes arrive as RGB888 (width * height * 3 bytes).
 */

#include "edge_veda.h"
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <mutex>
#include <time.h>

#ifdef EDGE_VEDA_LLAMA_ENABLED
#include "llama.h"
#include "ggml.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#endif

/* ============================================================================
 * Internal Structures
 * ========================================================================= */

struct ev_vision_context_impl {
    // Configuration
    ev_vision_config config;

    // Stored paths (owned copies)
    std::string model_path;
    std::string mmproj_path;

    // State
    bool model_loaded;
    std::string last_error;

    // Timing
    double last_image_encode_ms = 0.0;

    // Thread safety
    std::mutex mutex;

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // llama.cpp handles
    llama_model* model = nullptr;
    llama_context* llama_ctx = nullptr;

    // libmtmd handle
    mtmd_context* mtmd_ctx = nullptr;
#endif

    // Constructor
    ev_vision_context_impl()
        : model_loaded(false) {
    }

    ~ev_vision_context_impl() = default;
};

/* ============================================================================
 * Internal Helper: Sampler Creation (mirrors engine.cpp pattern)
 * ========================================================================= */

#ifdef EDGE_VEDA_LLAMA_ENABLED
/**
 * Create a sampler chain with the specified generation parameters.
 * Same pattern as engine.cpp create_sampler.
 */
static llama_sampler* vision_create_sampler(const ev_generation_params& params) {
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
 * Vision Configuration
 * ========================================================================= */

void ev_vision_config_default(ev_vision_config* config) {
    if (!config) return;

    std::memset(config, 0, sizeof(ev_vision_config));
    config->model_path = nullptr;
    config->mmproj_path = nullptr;
    config->num_threads = 0;           // Auto-detect
    config->context_size = 0;          // Auto (let model decide)
    config->batch_size = 512;
    config->memory_limit_bytes = 0;    // No limit
    config->gpu_layers = -1;           // All layers on GPU
    config->use_mmap = true;
    config->reserved = nullptr;
}

/* ============================================================================
 * Vision Context Management
 * ========================================================================= */

ev_vision_context ev_vision_init(
    const ev_vision_config* config,
    ev_error_t* error
) {
    if (!config || !config->model_path || !config->mmproj_path) {
        if (error) *error = EV_ERROR_INVALID_PARAM;
        return nullptr;
    }

    // Allocate context
    ev_vision_context ctx = new (std::nothrow) ev_vision_context_impl();
    if (!ctx) {
        if (error) *error = EV_ERROR_OUT_OF_MEMORY;
        return nullptr;
    }

    ctx->config = *config;
    ctx->model_path = config->model_path;
    ctx->mmproj_path = config->mmproj_path;

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Initialize llama.cpp backend
    llama_backend_init();

    // Configure model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = config->gpu_layers;
    model_params.use_mmap = config->use_mmap;

    // Load the VLM model
    ctx->model = llama_model_load_from_file(ctx->model_path.c_str(), model_params);
    if (!ctx->model) {
        ctx->last_error = "Failed to load VLM model from: " + ctx->model_path;
        llama_backend_free();
        delete ctx;
        if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
        return nullptr;
    }

    // Configure context parameters
    llama_context_params ctx_params = llama_context_default_params();

    // Context size: use config value, or model default if 0
    if (config->context_size > 0) {
        ctx_params.n_ctx = static_cast<uint32_t>(config->context_size);
    } else {
        // Use a reasonable default for vision models
        // SmolVLM2: ~2048 image tokens + prompt + output
        ctx_params.n_ctx = 4096;
    }

    ctx_params.n_batch = config->batch_size > 0
        ? static_cast<uint32_t>(config->batch_size)
        : 512;
    ctx_params.n_threads = config->num_threads > 0
        ? static_cast<uint32_t>(config->num_threads)
        : 4;
    ctx_params.n_threads_batch = ctx_params.n_threads;

    // Create llama context
    ctx->llama_ctx = llama_init_from_model(ctx->model, ctx_params);
    if (!ctx->llama_ctx) {
        ctx->last_error = "Failed to create llama context for VLM";
        llama_model_free(ctx->model);
        ctx->model = nullptr;
        llama_backend_free();
        delete ctx;
        if (error) *error = EV_ERROR_BACKEND_INIT_FAILED;
        return nullptr;
    }

    // Initialize mtmd (multimodal) context with mmproj
    mtmd_context_params mparams = mtmd_context_params_default();
    mparams.use_gpu = (config->gpu_layers != 0);
    mparams.print_timings = false;
    mparams.n_threads = config->num_threads > 0 ? config->num_threads : 4;
    mparams.warmup = true;  // Run warmup pass for optimal first-inference latency

    ctx->mtmd_ctx = mtmd_init_from_file(
        ctx->mmproj_path.c_str(),
        ctx->model,
        mparams
    );
    if (!ctx->mtmd_ctx) {
        ctx->last_error = "Failed to initialize multimodal context from: " + ctx->mmproj_path;
        llama_free(ctx->llama_ctx);
        ctx->llama_ctx = nullptr;
        llama_model_free(ctx->model);
        ctx->model = nullptr;
        llama_backend_free();
        delete ctx;
        if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
        return nullptr;
    }

    // Verify vision support
    if (!mtmd_support_vision(ctx->mtmd_ctx)) {
        ctx->last_error = "Model does not support vision input";
        mtmd_free(ctx->mtmd_ctx);
        ctx->mtmd_ctx = nullptr;
        llama_free(ctx->llama_ctx);
        ctx->llama_ctx = nullptr;
        llama_model_free(ctx->model);
        ctx->model = nullptr;
        llama_backend_free();
        delete ctx;
        if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
        return nullptr;
    }

    ctx->model_loaded = true;
    if (error) *error = EV_SUCCESS;
    return ctx;
#else
    ctx->last_error = "llama.cpp not compiled - library built without LLM support";
    delete ctx;
    if (error) *error = EV_ERROR_NOT_IMPLEMENTED;
    return nullptr;
#endif
}

void ev_vision_free(ev_vision_context ctx) {
    if (!ctx) return;

    std::lock_guard<std::mutex> lock(ctx->mutex);

#ifdef EDGE_VEDA_LLAMA_ENABLED
    if (ctx->mtmd_ctx) {
        mtmd_free(ctx->mtmd_ctx);
        ctx->mtmd_ctx = nullptr;
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

bool ev_vision_is_valid(ev_vision_context ctx) {
    return ctx != nullptr && ctx->model_loaded;
}

/* ============================================================================
 * Vision Inference (Image Description)
 * ========================================================================= */

ev_error_t ev_vision_describe(
    ev_vision_context ctx,
    const unsigned char* image_bytes,
    int width,
    int height,
    const char* prompt,
    const ev_generation_params* params,
    char** output
) {
    // Validate parameters
    if (!ctx || !image_bytes || !prompt || !output) {
        return EV_ERROR_INVALID_PARAM;
    }
    if (width <= 0 || height <= 0) {
        return EV_ERROR_INVALID_PARAM;
    }
    if (!ev_vision_is_valid(ctx)) {
        return EV_ERROR_CONTEXT_INVALID;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);

    // Resolve generation parameters
    ev_generation_params gen_params;
    if (params) {
        gen_params = *params;
    } else {
        ev_generation_params_default(&gen_params);
    }

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Clear KV cache for fresh generation
    llama_memory_clear(llama_get_memory(ctx->llama_ctx), true);

    // Step 1: Create bitmap from raw RGB888 image bytes
    // mtmd_bitmap_init expects: nx (width), ny (height), data (RGB interleaved)
    // Data length must be nx * ny * 3
    mtmd_bitmap* bitmap = mtmd_bitmap_init(
        static_cast<uint32_t>(width),
        static_cast<uint32_t>(height),
        image_bytes
    );
    if (!bitmap) {
        ctx->last_error = "Failed to create bitmap from image bytes";
        return EV_ERROR_OUT_OF_MEMORY;
    }

    // Step 2: Build prompt with media marker
    // The prompt format must include the media marker where the image goes.
    // We prepend the marker so the model sees the image first, then the question.
    const char* marker = mtmd_default_marker();
    std::string full_prompt = std::string(marker) + "\n" + prompt;

    // Step 3: Tokenize prompt + image via mtmd
    mtmd_input_chunks* chunks = mtmd_input_chunks_init();
    if (!chunks) {
        mtmd_bitmap_free(bitmap);
        ctx->last_error = "Failed to allocate input chunks";
        return EV_ERROR_OUT_OF_MEMORY;
    }

    mtmd_input_text text;
    text.text = full_prompt.c_str();
    text.add_special = true;   // Add BOS token
    text.parse_special = true; // Parse special tokens in text

    const mtmd_bitmap* bitmaps_arr[] = { bitmap };
    int32_t tokenize_result = mtmd_tokenize(
        ctx->mtmd_ctx,
        chunks,
        &text,
        bitmaps_arr,
        1  // one bitmap
    );

    // Bitmap data has been copied into chunks by mtmd_tokenize, free original
    mtmd_bitmap_free(bitmap);
    bitmap = nullptr;

    if (tokenize_result != 0) {
        mtmd_input_chunks_free(chunks);
        ctx->last_error = "Failed to tokenize prompt with image (error: "
                          + std::to_string(tokenize_result) + ")";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Step 4: Evaluate all chunks (text + image) using the helper
    // mtmd_helper_eval_chunks handles:
    //   - llama_decode for text chunks
    //   - mtmd_encode + llama_decode for image chunks
    // This is the recommended approach per mtmd-cli.cpp
    int32_t n_batch = static_cast<int32_t>(ctx->config.batch_size > 0
        ? ctx->config.batch_size : 512);
    llama_pos n_past = 0;
    llama_pos new_n_past = 0;

    struct timespec ts_start, ts_end;
    clock_gettime(CLOCK_MONOTONIC, &ts_start);

    int32_t eval_result = mtmd_helper_eval_chunks(
        ctx->mtmd_ctx,
        ctx->llama_ctx,
        chunks,
        n_past,      // start from position 0
        0,           // seq_id
        n_batch,
        true,        // logits_last (need logits for sampling)
        &new_n_past
    );

    clock_gettime(CLOCK_MONOTONIC, &ts_end);
    ctx->last_image_encode_ms = (ts_end.tv_sec - ts_start.tv_sec) * 1000.0
                               + (ts_end.tv_nsec - ts_start.tv_nsec) / 1e6;

    // Free chunks immediately after evaluation (P2 - memory explosion mitigation)
    // This releases image embeddings and all tokenization artifacts
    mtmd_input_chunks_free(chunks);
    chunks = nullptr;

    if (eval_result != 0) {
        ctx->last_error = "Failed to evaluate prompt+image chunks (error: "
                          + std::to_string(eval_result) + ")";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Step 5: Token generation loop (same pattern as engine.cpp)
    llama_sampler* sampler = vision_create_sampler(gen_params);
    if (!sampler) {
        ctx->last_error = "Failed to create sampler";
        return EV_ERROR_INFERENCE_FAILED;
    }

    std::string result;
    const llama_vocab* vocab = llama_model_get_vocab(ctx->model);

    for (int i = 0; i < gen_params.max_tokens; ++i) {
        // Sample next token
        llama_token new_token = llama_sampler_sample(sampler, ctx->llama_ctx, -1);

        // Check for end of generation
        if (llama_vocab_is_eog(vocab, new_token)) {
            break;
        }

        // Convert token to text
        char buf[256];
        int n = llama_token_to_piece(vocab, new_token, buf, sizeof(buf), 0, true);
        if (n > 0) {
            result.append(buf, static_cast<size_t>(n));
        }

        // Prepare single-token batch and decode (same pattern as engine.cpp)
        llama_batch batch = llama_batch_get_one(&new_token, 1);
        if (llama_decode(ctx->llama_ctx, batch) != 0) {
            llama_sampler_free(sampler);
            ctx->last_error = "Failed during token generation";
            return EV_ERROR_INFERENCE_FAILED;
        }
    }

    llama_sampler_free(sampler);

    // Allocate output string (caller frees with ev_free_string)
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

/* ============================================================================
 * Vision Timing / Performance Data
 * ========================================================================= */

ev_error_t ev_vision_get_last_timings(ev_vision_context ctx, ev_timings_data* timings) {
    if (!ctx || !timings) {
        return EV_ERROR_INVALID_PARAM;
    }
    if (!ctx->model_loaded) {
        return EV_ERROR_CONTEXT_INVALID;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    std::memset(timings, 0, sizeof(ev_timings_data));

#ifdef EDGE_VEDA_LLAMA_ENABLED
    struct llama_perf_context_data perf = llama_perf_context(ctx->llama_ctx);
    timings->model_load_ms    = perf.t_load_ms;
    timings->prompt_eval_ms   = perf.t_p_eval_ms;
    timings->decode_ms        = perf.t_eval_ms;
    timings->prompt_tokens    = perf.n_p_eval;
    timings->generated_tokens = perf.n_eval;
    timings->image_encode_ms  = ctx->last_image_encode_ms;
#endif

    return EV_SUCCESS;
}
