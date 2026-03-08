#pragma once

/**
 * @file memory_guard.h
 * @brief Memory guard public API for cross-engine memory coordination
 *
 * Provides process-wide memory monitoring, per-engine registration with
 * LRU eviction, and recommended limit tiering by platform/device.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Engine IDs for the registry */
#define MG_ENGINE_LLM     0
#define MG_ENGINE_VISION   1
#define MG_ENGINE_WHISPER  2
#define MG_ENGINE_IMAGE    3
#define MG_ENGINE_COUNT    4

/* ---- Existing API ---- */

size_t memory_guard_get_current_usage(void);
size_t memory_guard_get_peak_usage(void);
size_t memory_guard_get_total_memory(void);
void   memory_guard_set_limit(size_t limit_bytes);
size_t memory_guard_get_limit(void);
void   memory_guard_set_callback(void (*callback)(void*, size_t, size_t), void* user_data);
void   memory_guard_set_threshold(float threshold);
void   memory_guard_set_check_interval(int interval_ms);
void   memory_guard_set_auto_cleanup(bool enable);
void   memory_guard_cleanup(void);
void   memory_guard_reset_stats(void);
void   memory_guard_start(void);
void   memory_guard_stop(void);
void   memory_guard_init(void);
void   memory_guard_shutdown(void);
float  memory_guard_get_usage_percentage(void);
bool   memory_guard_is_under_pressure(void);
size_t memory_guard_get_recommended_limit(void);

/* ---- Engine Registry API (Phase 2) ---- */

/**
 * Register an engine with the memory guard.
 *
 * On the first registration, the process-wide limit is auto-set from
 * memory_guard_get_recommended_limit() if no limit has been set yet,
 * and monitoring starts automatically.
 *
 * @param engine_id   One of MG_ENGINE_* constants
 * @param footprint   Approximate memory footprint in bytes
 * @param evict_cb    Callback invoked to evict (unload) this engine under pressure.
 *                    Called with mutex released. Must be safe to call from monitor thread.
 *                    May be NULL if engine does not support eviction.
 * @param user_data   Opaque pointer passed to evict_cb
 */
void memory_guard_register_engine(
    int engine_id,
    size_t footprint,
    void (*evict_cb)(void* user_data),
    void* user_data
);

/**
 * Unregister an engine from the memory guard.
 * Called from engine free paths.
 */
void memory_guard_unregister_engine(int engine_id);

/**
 * Update an engine's last-use timestamp (for LRU ordering).
 * Call at the start of each inference to keep active engines from eviction.
 */
void memory_guard_touch_engine(int engine_id);

/**
 * Get total registered engine memory footprint across all engines.
 */
size_t memory_guard_get_total_engine_footprint(void);

/**
 * Check if a proposed new engine load fits within the budget.
 * @return 0 if fits, 1 if fits after evicting LRU, -1 if cannot fit even after eviction
 */
int memory_guard_check_budget(size_t proposed_bytes);

#ifdef __cplusplus
}
#endif
