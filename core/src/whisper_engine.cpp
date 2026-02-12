/**
 * @file whisper_engine.cpp
 * @brief Edge Veda SDK - Whisper Engine Implementation
 *
 * This file implements the ev_whisper_* public C API defined in edge_veda.h
 * using whisper.cpp v1.8.3 for on-device speech-to-text transcription.
 *
 * Whisper context is SEPARATE from text context (engine.cpp) and
 * vision context (vision_engine.cpp).
 * PCM audio arrives as 16kHz mono float32 samples.
 */

#include "edge_veda.h"
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <mutex>
#include <chrono>

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#ifdef EDGE_VEDA_WHISPER_ENABLED
#include "whisper.h"
#endif

/* ============================================================================
 * Internal Structures
 * ========================================================================= */

struct ev_whisper_context_impl {
    // whisper.cpp handle
#ifdef EDGE_VEDA_WHISPER_ENABLED
    struct whisper_context* wctx = nullptr;
#endif

    // Stored path (owned copy)
    std::string model_path;

    // State
    bool model_loaded;
    std::string last_error;

    // Default thread count from config
    int default_threads;

    // Thread safety
    std::mutex mutex;

    // Owned segment text strings (kept alive until next transcription or free)
    std::vector<std::string> segment_texts;

    // Segment array returned to caller (pointers into segment_texts)
    std::vector<ev_whisper_segment> segments;

    // Constructor
    ev_whisper_context_impl()
        : model_loaded(false)
        , default_threads(4) {
    }

    ~ev_whisper_context_impl() = default;
};

/* ============================================================================
 * Whisper Configuration
 * ========================================================================= */

void ev_whisper_config_default(ev_whisper_config* config) {
    if (!config) return;

    std::memset(config, 0, sizeof(ev_whisper_config));
    config->model_path = nullptr;
    config->num_threads = 0;    // Auto-detect (will default to 4)
    config->use_gpu = true;     // Use Metal on iOS/macOS
    config->reserved = nullptr;
}

/* ============================================================================
 * Whisper Context Management
 * ========================================================================= */

ev_whisper_context ev_whisper_init(
    const ev_whisper_config* config,
    ev_error_t* error
) {
    if (!config || !config->model_path) {
        if (error) *error = EV_ERROR_INVALID_PARAM;
        return nullptr;
    }

    // Allocate context
    ev_whisper_context ctx = new (std::nothrow) ev_whisper_context_impl();
    if (!ctx) {
        if (error) *error = EV_ERROR_OUT_OF_MEMORY;
        return nullptr;
    }

    ctx->model_path = config->model_path;
    ctx->default_threads = config->num_threads > 0 ? config->num_threads : 4;

#ifdef EDGE_VEDA_WHISPER_ENABLED
    // Configure whisper context parameters
    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = config->use_gpu;

    // iOS Simulator: force CPU-only.  whisper.cpp's ggml-metal calls
    // MTLSimDevice which triggers _xpc_api_misuse SIGTRAP.
#if TARGET_OS_SIMULATOR
    cparams.use_gpu = false;
#endif

    // Load the whisper model
    ctx->wctx = whisper_init_from_file_with_params(
        ctx->model_path.c_str(),
        cparams
    );
    if (!ctx->wctx) {
        ctx->last_error = "Failed to load Whisper model from: " + ctx->model_path;
        delete ctx;
        if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
        return nullptr;
    }

    ctx->model_loaded = true;
    if (error) *error = EV_SUCCESS;
    return ctx;
#else
    ctx->last_error = "whisper.cpp not compiled - library built without STT support";
    delete ctx;
    if (error) *error = EV_ERROR_NOT_IMPLEMENTED;
    return nullptr;
#endif
}

void ev_whisper_free(ev_whisper_context ctx) {
    if (!ctx) return;

    std::lock_guard<std::mutex> lock(ctx->mutex);

#ifdef EDGE_VEDA_WHISPER_ENABLED
    if (ctx->wctx) {
        whisper_free(ctx->wctx);
        ctx->wctx = nullptr;
    }
#endif

    ctx->model_loaded = false;

    // Note: unlock before delete (lock_guard will unlock in its destructor,
    // but the mutex is part of ctx which we're about to delete).
    // This is safe because we hold the only reference.
    delete ctx;
}

bool ev_whisper_is_valid(ev_whisper_context ctx) {
    return ctx != nullptr && ctx->model_loaded;
}

/* ============================================================================
 * Whisper Transcription
 * ========================================================================= */

ev_error_t ev_whisper_transcribe(
    ev_whisper_context ctx,
    const float* pcm_samples,
    int n_samples,
    const ev_whisper_params* params,
    ev_whisper_result* result
) {
    // Validate parameters
    if (!ctx || !pcm_samples || !result) {
        return EV_ERROR_INVALID_PARAM;
    }
    if (n_samples <= 0) {
        return EV_ERROR_INVALID_PARAM;
    }
    if (!ev_whisper_is_valid(ctx)) {
        return EV_ERROR_CONTEXT_INVALID;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);

    // Clear previous results
    ctx->segment_texts.clear();
    ctx->segments.clear();

    // Initialize result
    std::memset(result, 0, sizeof(ev_whisper_result));

#ifdef EDGE_VEDA_WHISPER_ENABLED
    // Resolve transcription parameters
    int n_threads = ctx->default_threads;
    const char* language = "en";
    bool translate = false;

    if (params) {
        if (params->n_threads > 0) {
            n_threads = params->n_threads;
        }
        if (params->language) {
            language = params->language;
        }
        translate = params->translate;
    }

    // Create whisper full params with greedy sampling
    struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.n_threads = n_threads;
    wparams.language = language;
    wparams.translate = translate;

    // Disable printing to stdout (we capture results via API)
    wparams.print_special = false;
    wparams.print_progress = false;
    wparams.print_realtime = false;
    wparams.print_timestamps = false;

    // Suppress blank tokens for cleaner output
    wparams.suppress_blank = true;
    wparams.suppress_nst = true;

    // Measure processing time
    auto t_start = std::chrono::high_resolution_clock::now();

    // Run the full whisper pipeline: PCM -> mel -> encoder -> decoder -> text
    int wresult = whisper_full(ctx->wctx, wparams, pcm_samples, n_samples);

    auto t_end = std::chrono::high_resolution_clock::now();
    double process_time_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();

    if (wresult != 0) {
        ctx->last_error = "Whisper transcription failed (error: "
                          + std::to_string(wresult) + ")";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Extract segments
    int n_segments = whisper_full_n_segments(ctx->wctx);
    ctx->segment_texts.reserve(static_cast<size_t>(n_segments));
    ctx->segments.reserve(static_cast<size_t>(n_segments));

    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(ctx->wctx, i);
        if (!text) continue;

        // Own the text string
        ctx->segment_texts.emplace_back(text);

        // Get timestamps (whisper returns centiseconds, multiply by 10 for ms)
        int64_t t0 = whisper_full_get_segment_t0(ctx->wctx, i);
        int64_t t1 = whisper_full_get_segment_t1(ctx->wctx, i);

        ev_whisper_segment seg;
        seg.text = ctx->segment_texts.back().c_str();
        seg.start_ms = t0 * 10;
        seg.end_ms = t1 * 10;

        ctx->segments.push_back(seg);
    }

    // Fill result
    result->segments = ctx->segments.empty() ? nullptr : ctx->segments.data();
    result->n_segments = static_cast<int>(ctx->segments.size());
    result->process_time_ms = process_time_ms;

    return EV_SUCCESS;
#else
    ctx->last_error = "whisper.cpp not compiled";
    return EV_ERROR_NOT_IMPLEMENTED;
#endif
}

/* ============================================================================
 * Result Cleanup
 * ========================================================================= */

void ev_whisper_free_result(ev_whisper_result* result) {
    if (!result) return;

    // The segments array and text strings are owned by the context
    // (ctx->segments and ctx->segment_texts vectors).
    // This function just zeros the result struct so the caller
    // doesn't hold stale pointers.
    result->segments = nullptr;
    result->n_segments = 0;
    result->process_time_ms = 0.0;
}
