/**
 * @file image_engine.cpp
 * @brief Edge Veda SDK - Image Generation Engine Implementation
 *
 * This file implements the ev_image_* public C API defined in edge_veda.h
 * using stable-diffusion.cpp for on-device text-to-image generation.
 *
 * Image context is SEPARATE from text context (engine.cpp), vision context
 * (vision_engine.cpp), and whisper context (whisper_engine.cpp).
 * A text prompt arrives, and raw RGB pixels come back.
 */

#include "edge_veda.h"
#include <cstring>
#include <cstdlib>
#include <string>
#include <mutex>

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#ifdef EDGE_VEDA_SD_ENABLED
#include "stable-diffusion.h"
#endif

/* ============================================================================
 * Internal Structures
 * ========================================================================= */

struct ev_image_context_impl {
    // stable-diffusion.cpp handle
#ifdef EDGE_VEDA_SD_ENABLED
    sd_ctx_t* sd_ctx = nullptr;
#endif

    // Stored path (owned copy)
    std::string model_path;

    // State
    bool model_loaded;
    std::string last_error;

    // Default thread count from config
    int default_threads;

    // Progress callback
    ev_image_progress_cb progress_cb;
    void* progress_user_data;

    // Thread safety
    std::mutex mutex;

    // Constructor
    ev_image_context_impl()
        : model_loaded(false)
        , default_threads(4)
        , progress_cb(nullptr)
        , progress_user_data(nullptr) {
    }

    ~ev_image_context_impl() = default;
};

/* ============================================================================
 * Progress Callback Bridge
 *
 * sd.cpp uses a global progress callback (sd_set_progress_callback).
 * We store a thread-local pointer to the active context so the global
 * callback can dispatch to the per-context callback.
 * ========================================================================= */

#ifdef EDGE_VEDA_SD_ENABLED
static thread_local ev_image_context_impl* g_active_image_ctx = nullptr;

static void sd_progress_bridge(int step, int steps, float time, void* /* data */) {
    ev_image_context_impl* ctx = g_active_image_ctx;
    if (ctx && ctx->progress_cb) {
        ctx->progress_cb(step, steps, time, ctx->progress_user_data);
    }
}
#endif

/* ============================================================================
 * Sampler / Schedule Mapping
 * ========================================================================= */

#ifdef EDGE_VEDA_SD_ENABLED
static enum sample_method_t map_sampler(ev_image_sampler_t sampler) {
    switch (sampler) {
        case EV_SAMPLER_EULER_A:          return EULER_A_SAMPLE_METHOD;
        case EV_SAMPLER_EULER:            return EULER_SAMPLE_METHOD;
        case EV_SAMPLER_DPM_PLUS_PLUS_2M: return DPMPP2M_SAMPLE_METHOD;
        case EV_SAMPLER_DPM_PLUS_PLUS_2S_A: return DPMPP2S_A_SAMPLE_METHOD;
        case EV_SAMPLER_LCM:             return LCM_SAMPLE_METHOD;
        default:                          return EULER_A_SAMPLE_METHOD;
    }
}

static enum scheduler_t map_schedule(ev_image_schedule_t schedule) {
    switch (schedule) {
        case EV_SCHEDULE_DEFAULT:  return DISCRETE_SCHEDULER;
        case EV_SCHEDULE_DISCRETE: return DISCRETE_SCHEDULER;
        case EV_SCHEDULE_KARRAS:   return KARRAS_SCHEDULER;
        case EV_SCHEDULE_AYS:      return AYS_SCHEDULER;
        default:                   return DISCRETE_SCHEDULER;
    }
}
#endif

/* ============================================================================
 * Image Configuration
 * ========================================================================= */

void ev_image_config_default(ev_image_config* config) {
    if (!config) return;

    std::memset(config, 0, sizeof(ev_image_config));
    config->model_path = nullptr;
    config->num_threads = 0;    // Auto-detect (will default to 4)
    config->use_gpu = true;     // Use Metal on iOS/macOS
    config->wtype = -1;         // Auto from GGUF
    config->reserved = nullptr;
}

void ev_image_gen_params_default(ev_image_gen_params* params) {
    if (!params) return;

    std::memset(params, 0, sizeof(ev_image_gen_params));
    params->prompt = nullptr;
    params->negative_prompt = nullptr;
    params->width = 512;
    params->height = 512;
    params->steps = 4;          // Turbo default (1-4 steps)
    params->cfg_scale = 1.0f;   // Turbo works best with low guidance
    params->seed = -1;          // Random
    params->sampler = EV_SAMPLER_EULER_A;
    params->schedule = EV_SCHEDULE_DEFAULT;
    params->reserved = nullptr;
}

/* ============================================================================
 * Image Context Management
 * ========================================================================= */

ev_image_context ev_image_init(
    const ev_image_config* config,
    ev_error_t* error
) {
    if (!config || !config->model_path) {
        if (error) *error = EV_ERROR_INVALID_PARAM;
        return nullptr;
    }

    // Allocate context
    ev_image_context ctx = new (std::nothrow) ev_image_context_impl();
    if (!ctx) {
        if (error) *error = EV_ERROR_OUT_OF_MEMORY;
        return nullptr;
    }

    ctx->model_path = config->model_path;
    ctx->default_threads = config->num_threads > 0 ? config->num_threads : 4;

#ifdef EDGE_VEDA_SD_ENABLED
    // Configure sd.cpp context parameters
    sd_ctx_params_t sd_params;
    sd_ctx_params_init(&sd_params);

    sd_params.model_path = ctx->model_path.c_str();
    sd_params.n_threads = ctx->default_threads;
    sd_params.vae_decode_only = true;   // Text-to-image only (no encoding)
    sd_params.free_params_immediately = true;  // Free encoder params after load

    // Weight type override
    if (config->wtype >= 0 && config->wtype < SD_TYPE_COUNT) {
        sd_params.wtype = static_cast<enum sd_type_t>(config->wtype);
    }

    // GPU configuration
    bool use_gpu = config->use_gpu;

    // iOS Simulator: force CPU-only. ggml-metal calls MTLSimDevice
    // which triggers _xpc_api_misuse SIGTRAP on simulator.
#if TARGET_OS_SIMULATOR
    use_gpu = false;
#endif

    if (use_gpu) {
        sd_params.flash_attn = true;
        sd_params.diffusion_flash_attn = true;
    }

    // Install progress callback bridge
    sd_set_progress_callback(sd_progress_bridge, nullptr);

    // Create the sd.cpp context (loads the model)
    ctx->sd_ctx = new_sd_ctx(&sd_params);
    if (!ctx->sd_ctx) {
        ctx->last_error = "Failed to load SD model from: " + ctx->model_path;
        delete ctx;
        if (error) *error = EV_ERROR_MODEL_LOAD_FAILED;
        return nullptr;
    }

    ctx->model_loaded = true;
    if (error) *error = EV_SUCCESS;
    return ctx;
#else
    ctx->last_error = "stable-diffusion.cpp not compiled - library built without image generation support";
    delete ctx;
    if (error) *error = EV_ERROR_NOT_IMPLEMENTED;
    return nullptr;
#endif
}

void ev_image_free(ev_image_context ctx) {
    if (!ctx) return;

    std::lock_guard<std::mutex> lock(ctx->mutex);

#ifdef EDGE_VEDA_SD_ENABLED
    if (ctx->sd_ctx) {
        free_sd_ctx(ctx->sd_ctx);
        ctx->sd_ctx = nullptr;
    }
#endif

    ctx->model_loaded = false;

    // Note: unlock before delete (lock_guard will unlock in its destructor,
    // but the mutex is part of ctx which we're about to delete).
    // This is safe because we hold the only reference.
    delete ctx;
}

bool ev_image_is_valid(ev_image_context ctx) {
    return ctx != nullptr && ctx->model_loaded;
}

void ev_image_set_progress_callback(ev_image_context ctx, ev_image_progress_cb cb, void* user_data) {
    if (!ctx) return;

    std::lock_guard<std::mutex> lock(ctx->mutex);
    ctx->progress_cb = cb;
    ctx->progress_user_data = user_data;
}

/* ============================================================================
 * Image Generation
 * ========================================================================= */

ev_error_t ev_image_generate(
    ev_image_context ctx,
    const ev_image_gen_params* params,
    ev_image_result* result
) {
    // Validate parameters
    if (!ctx || !params || !result) {
        return EV_ERROR_INVALID_PARAM;
    }
    if (!params->prompt) {
        return EV_ERROR_INVALID_PARAM;
    }
    if (!ev_image_is_valid(ctx)) {
        return EV_ERROR_CONTEXT_INVALID;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);

    // Initialize result
    std::memset(result, 0, sizeof(ev_image_result));

#ifdef EDGE_VEDA_SD_ENABLED
    // Set this context as the active one for the progress callback bridge
    g_active_image_ctx = ctx;

    // Build sd.cpp generation parameters
    sd_img_gen_params_t gen_params;
    sd_img_gen_params_init(&gen_params);

    gen_params.prompt = params->prompt;
    gen_params.negative_prompt = params->negative_prompt ? params->negative_prompt : "";
    gen_params.width = params->width > 0 ? params->width : 512;
    gen_params.height = params->height > 0 ? params->height : 512;
    gen_params.seed = params->seed;

    // Sampling parameters
    gen_params.sample_params.sample_steps = params->steps > 0 ? params->steps : 4;
    gen_params.sample_params.guidance.txt_cfg = params->cfg_scale > 0.0f ? params->cfg_scale : 1.0f;
    gen_params.sample_params.sample_method = map_sampler(params->sampler);
    gen_params.sample_params.scheduler = map_schedule(params->schedule);

    // Single image (batch_count = 1)
    gen_params.batch_count = 1;

    // Run the full diffusion pipeline (blocking)
    sd_image_t* images = generate_image(ctx->sd_ctx, &gen_params);

    // Clear active context
    g_active_image_ctx = nullptr;

    if (!images || !images[0].data) {
        ctx->last_error = "Image generation failed";
        return EV_ERROR_INFERENCE_FAILED;
    }

    // Copy the result pixels into our own allocation
    // sd.cpp returns sd_image_t with data owned by sd.cpp (freed on next call)
    uint32_t w = images[0].width;
    uint32_t h = images[0].height;
    uint32_t c = images[0].channel;
    size_t data_size = (size_t)w * h * c;

    uint8_t* data_copy = static_cast<uint8_t*>(std::malloc(data_size));
    if (!data_copy) {
        // Free the sd.cpp images
        free(images[0].data);
        free(images);
        return EV_ERROR_OUT_OF_MEMORY;
    }

    std::memcpy(data_copy, images[0].data, data_size);

    // Free sd.cpp's image data
    free(images[0].data);
    free(images);

    // Fill result
    result->data = data_copy;
    result->width = w;
    result->height = h;
    result->channels = c;
    result->data_size = data_size;

    return EV_SUCCESS;
#else
    ctx->last_error = "stable-diffusion.cpp not compiled";
    return EV_ERROR_NOT_IMPLEMENTED;
#endif
}

/* ============================================================================
 * Result Cleanup
 * ========================================================================= */

void ev_image_free_result(ev_image_result* result) {
    if (!result) return;

    if (result->data) {
        std::free(result->data);
    }

    result->data = nullptr;
    result->width = 0;
    result->height = 0;
    result->channels = 0;
    result->data_size = 0;
}
