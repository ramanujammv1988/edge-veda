/**
 * @file test_memory_guard.cpp
 * @brief CI-safe unit tests for memory guard and backend lifecycle
 *
 * Tests memory guard recommended limits, set/get operations,
 * and backend lifecycle reference counting. No model file needed.
 */

#include "edge_veda.h"
#include "memory_guard.h"
#include <cstdio>
#include <cstddef>
#include <cstdint>

// Backend lifecycle (guarded by EDGE_VEDA_LLAMA_ENABLED at link time)
#include "backend_lifecycle.h"

// ANSI colors for output
#define GREEN  "\033[32m"
#define RED    "\033[31m"
#define RESET  "\033[0m"

static void print_pass(const char* test) {
    printf(GREEN "[PASS]" RESET " %s\n", test);
}

static void print_fail(const char* test, const char* reason) {
    printf(RED "[FAIL]" RESET " %s: %s\n", test, reason);
}

#define TEST(name) do { \
    int _r = name(); \
    if (_r == 0) { passes++; print_pass(#name); } \
    else { failures++; print_fail(#name, "assertion failed"); } \
} while(0)

// ---------- Memory guard: recommended limit ----------

int test_memory_guard_recommended_limit_nonzero() {
    size_t limit = memory_guard_get_recommended_limit();
    if (limit == 0) return 1;
    return 0;
}

int test_memory_guard_recommended_limit_reasonable() {
    size_t total = memory_guard_get_total_memory();
    size_t limit = memory_guard_get_recommended_limit();
    if (total == 0 || limit == 0) return 1;

    // Limit should never exceed total memory
    if (limit > total) return 1;

#if defined(__APPLE__) && !defined(__ANDROID__)
    // macOS/iOS: fixed 1.2GB = 1,258,291,200 bytes
    size_t expected = (size_t)1200 * 1024 * 1024;
    if (limit != expected) return 1;
#elif !defined(__ANDROID__)
    // Desktop (non-Apple, non-Android): 60% of total
    size_t expected = (size_t)(total * 0.6);
    size_t tolerance = total / 100; // 1% tolerance for rounding
    if (limit < expected - tolerance || limit > expected + tolerance) return 1;
#endif
    // Android tiers (800MB/1GB/1.2GB) are only testable on Android builds

    return 0;
}

int test_memory_guard_total_memory_nonzero() {
    size_t total = memory_guard_get_total_memory();
    if (total == 0) return 1;
    return 0;
}

// ---------- Memory guard: set/get limit ----------

int test_memory_guard_set_get_limit() {
    size_t original = memory_guard_get_limit();

    memory_guard_set_limit(500 * 1024 * 1024); // 500MB
    size_t got = memory_guard_get_limit();
    if (got != 500 * 1024 * 1024) {
        memory_guard_set_limit(original);
        return 1;
    }

    // Restore
    memory_guard_set_limit(original);
    return 0;
}

int test_memory_guard_set_limit_zero() {
    size_t original = memory_guard_get_limit();

    memory_guard_set_limit(0);
    size_t got = memory_guard_get_limit();

    memory_guard_set_limit(original);
    if (got != 0) return 1;
    return 0;
}

// ---------- Memory guard: usage percentage ----------

int test_memory_guard_usage_percentage_no_limit() {
    size_t original = memory_guard_get_limit();
    memory_guard_set_limit(0);

    float pct = memory_guard_get_usage_percentage();
    // With no limit set, returns -1.0f (sentinel value)
    memory_guard_set_limit(original);
    if (pct != -1.0f) return 1;
    return 0;
}

// ---------- Memory guard: pressure check ----------

int test_memory_guard_not_under_pressure_no_limit() {
    size_t original = memory_guard_get_limit();
    memory_guard_set_limit(0);

    bool pressure = memory_guard_is_under_pressure();
    memory_guard_set_limit(original);
    // With no limit, should not be under pressure
    if (pressure) return 1;
    return 0;
}

// ---------- Memory guard: callback set/clear ----------

int test_memory_guard_set_callback_null() {
    // Setting NULL callback should not crash
    memory_guard_set_callback(NULL, NULL);
    return 0;
}

// ---------- Memory guard: reset stats ----------

int test_memory_guard_reset_stats_no_crash() {
    memory_guard_reset_stats();
    return 0;
}

// ---------- Memory guard: threshold ----------

int test_memory_guard_set_threshold() {
    // Setting threshold should not crash
    memory_guard_set_threshold(0.85f);
    // Restore default
    memory_guard_set_threshold(0.90f);
    return 0;
}

// ---------- Backend lifecycle ----------

#ifdef EDGE_VEDA_LLAMA_ENABLED

int test_backend_acquire_release_single() {
    edge_veda_backend_acquire();
    edge_veda_backend_release();
    return 0;
}

int test_backend_acquire_release_multiple() {
    for (int i = 0; i < 5; i++) {
        edge_veda_backend_acquire();
    }
    for (int i = 0; i < 5; i++) {
        edge_veda_backend_release();
    }
    return 0;
}

int test_backend_extra_release_no_crash() {
    // Extra release without acquire should not crash
    edge_veda_backend_release();
    return 0;
}

int test_backend_reacquire_after_full_release() {
    edge_veda_backend_acquire();
    edge_veda_backend_release();
    // Backend freed; re-acquire should reinitialize
    edge_veda_backend_acquire();
    edge_veda_backend_release();
    return 0;
}

#endif // EDGE_VEDA_LLAMA_ENABLED

// ---------- Engine registry: register / unregister ----------

int test_engine_registry_register_unregister() {
    // Register LLM engine with 500MB footprint and no eviction callback
    memory_guard_register_engine(MG_ENGINE_LLM, 500 * 1024 * 1024, NULL, NULL);

    size_t footprint = memory_guard_get_total_engine_footprint();
    if (footprint != 500 * 1024 * 1024) {
        memory_guard_unregister_engine(MG_ENGINE_LLM);
        return 1;
    }

    memory_guard_unregister_engine(MG_ENGINE_LLM);

    footprint = memory_guard_get_total_engine_footprint();
    if (footprint != 0) return 1;

    return 0;
}

int test_engine_registry_multiple_engines() {
    memory_guard_register_engine(MG_ENGINE_LLM, 400 * 1024 * 1024, NULL, NULL);
    memory_guard_register_engine(MG_ENGINE_VISION, 300 * 1024 * 1024, NULL, NULL);
    memory_guard_register_engine(MG_ENGINE_WHISPER, 100 * 1024 * 1024, NULL, NULL);

    size_t footprint = memory_guard_get_total_engine_footprint();
    size_t expected = (size_t)(400 + 300 + 100) * 1024 * 1024;
    if (footprint != expected) {
        memory_guard_unregister_engine(MG_ENGINE_LLM);
        memory_guard_unregister_engine(MG_ENGINE_VISION);
        memory_guard_unregister_engine(MG_ENGINE_WHISPER);
        return 1;
    }

    memory_guard_unregister_engine(MG_ENGINE_LLM);
    memory_guard_unregister_engine(MG_ENGINE_VISION);
    memory_guard_unregister_engine(MG_ENGINE_WHISPER);
    return 0;
}

int test_engine_registry_double_register() {
    // Second register should overwrite first
    memory_guard_register_engine(MG_ENGINE_LLM, 500 * 1024 * 1024, NULL, NULL);
    memory_guard_register_engine(MG_ENGINE_LLM, 300 * 1024 * 1024, NULL, NULL);

    size_t footprint = memory_guard_get_total_engine_footprint();
    if (footprint != 300 * 1024 * 1024) {
        memory_guard_unregister_engine(MG_ENGINE_LLM);
        return 1;
    }

    memory_guard_unregister_engine(MG_ENGINE_LLM);
    return 0;
}

int test_engine_registry_unregister_inactive() {
    // Unregistering an already-inactive engine should not crash
    memory_guard_unregister_engine(MG_ENGINE_WHISPER);
    return 0;
}

int test_engine_registry_out_of_range() {
    // Out-of-range engine IDs should be silently ignored
    memory_guard_register_engine(-1, 100, NULL, NULL);
    memory_guard_register_engine(MG_ENGINE_COUNT, 100, NULL, NULL);
    memory_guard_unregister_engine(-1);
    memory_guard_unregister_engine(MG_ENGINE_COUNT);
    memory_guard_touch_engine(-1);
    memory_guard_touch_engine(MG_ENGINE_COUNT);

    // Footprint should be 0 (nothing registered)
    size_t footprint = memory_guard_get_total_engine_footprint();
    if (footprint != 0) return 1;
    return 0;
}

// ---------- Engine registry: touch ----------

int test_engine_registry_touch_no_crash() {
    memory_guard_register_engine(MG_ENGINE_LLM, 100, NULL, NULL);
    memory_guard_touch_engine(MG_ENGINE_LLM);
    memory_guard_unregister_engine(MG_ENGINE_LLM);
    return 0;
}

int test_engine_registry_touch_inactive() {
    // Touching an inactive engine should not crash
    memory_guard_touch_engine(MG_ENGINE_IMAGE);
    return 0;
}

// ---------- Engine registry: budget check ----------

int test_engine_registry_budget_fits() {
    size_t original_limit = memory_guard_get_limit();

    memory_guard_set_limit(1000 * 1024 * 1024); // 1000MB limit
    memory_guard_register_engine(MG_ENGINE_LLM, 400 * 1024 * 1024, NULL, NULL);

    // 300MB proposed should fit (400 + 300 = 700 < 1000)
    int result = memory_guard_check_budget(300 * 1024 * 1024);

    memory_guard_unregister_engine(MG_ENGINE_LLM);
    memory_guard_set_limit(original_limit);

    if (result != 0) return 1;
    return 0;
}

int test_engine_registry_budget_no_limit() {
    size_t original_limit = memory_guard_get_limit();
    memory_guard_set_limit(0);

    // With no limit, everything fits
    int result = memory_guard_check_budget(999999999);

    memory_guard_set_limit(original_limit);
    if (result != 0) return 1;
    return 0;
}

int test_engine_registry_budget_exceeds() {
    size_t original_limit = memory_guard_get_limit();
    memory_guard_set_limit(500 * 1024 * 1024); // 500MB limit

    memory_guard_register_engine(MG_ENGINE_LLM, 400 * 1024 * 1024, NULL, NULL);

    // 200MB proposed won't fit (400 + 200 = 600 > 500), no evictable engines (NULL callback)
    int result = memory_guard_check_budget(200 * 1024 * 1024);

    memory_guard_unregister_engine(MG_ENGINE_LLM);
    memory_guard_set_limit(original_limit);

    if (result != -1) return 1;
    return 0;
}

static void dummy_evict_cb(void* /* user_data */) {
    // No-op eviction callback for testing
}

int test_engine_registry_budget_fits_after_eviction() {
    size_t original_limit = memory_guard_get_limit();
    memory_guard_set_limit(500 * 1024 * 1024); // 500MB limit

    // Register LLM with eviction callback (400MB)
    memory_guard_register_engine(MG_ENGINE_LLM, 400 * 1024 * 1024, dummy_evict_cb, NULL);

    // 200MB proposed: 400 + 200 = 600 > 500, but 400MB is evictable → 0 + 200 = 200 < 500
    int result = memory_guard_check_budget(200 * 1024 * 1024);

    memory_guard_unregister_engine(MG_ENGINE_LLM);
    memory_guard_set_limit(original_limit);

    if (result != 1) return 1; // 1 = fits after eviction
    return 0;
}

// ---------- Engine registry: auto-limit on first registration ----------

int test_engine_registry_auto_limit() {
    // Shutdown to clear any limit
    memory_guard_shutdown();

    size_t limit_before = memory_guard_get_limit();
    if (limit_before != 0) return 1; // Should be 0 after shutdown

    // Register an engine — should auto-set recommended limit
    memory_guard_register_engine(MG_ENGINE_LLM, 100, NULL, NULL);

    size_t limit_after = memory_guard_get_limit();
    memory_guard_unregister_engine(MG_ENGINE_LLM);

    // Limit should now be non-zero (the recommended limit)
    if (limit_after == 0) return 1;

    // Clean up
    memory_guard_shutdown();
    return 0;
}

// ---------- Main ----------

int main() {
    printf("\n=== Edge Veda Memory Guard & Backend Lifecycle Tests ===\n\n");

    int passes = 0;
    int failures = 0;

    // Memory guard: recommended limit
    TEST(test_memory_guard_recommended_limit_nonzero);
    TEST(test_memory_guard_recommended_limit_reasonable);
    TEST(test_memory_guard_total_memory_nonzero);

    // Memory guard: set/get
    TEST(test_memory_guard_set_get_limit);
    TEST(test_memory_guard_set_limit_zero);

    // Memory guard: usage and pressure
    TEST(test_memory_guard_usage_percentage_no_limit);
    TEST(test_memory_guard_not_under_pressure_no_limit);

    // Memory guard: callback and stats
    TEST(test_memory_guard_set_callback_null);
    TEST(test_memory_guard_reset_stats_no_crash);
    TEST(test_memory_guard_set_threshold);

    // Engine registry: register / unregister
    TEST(test_engine_registry_register_unregister);
    TEST(test_engine_registry_multiple_engines);
    TEST(test_engine_registry_double_register);
    TEST(test_engine_registry_unregister_inactive);
    TEST(test_engine_registry_out_of_range);

    // Engine registry: touch
    TEST(test_engine_registry_touch_no_crash);
    TEST(test_engine_registry_touch_inactive);

    // Engine registry: budget check
    TEST(test_engine_registry_budget_fits);
    TEST(test_engine_registry_budget_no_limit);
    TEST(test_engine_registry_budget_exceeds);
    TEST(test_engine_registry_budget_fits_after_eviction);

    // Engine registry: auto-limit
    TEST(test_engine_registry_auto_limit);

    // Backend lifecycle
#ifdef EDGE_VEDA_LLAMA_ENABLED
    TEST(test_backend_acquire_release_single);
    TEST(test_backend_acquire_release_multiple);
    TEST(test_backend_extra_release_no_crash);
    TEST(test_backend_reacquire_after_full_release);
#endif

    // Summary
    printf("\n=== Test Summary ===\n");
    printf("Passed: %d\n", passes);
    printf("Failed: %d\n", failures);

    if (failures == 0) {
        printf(GREEN "\nAll tests passed!\n" RESET);
        return 0;
    } else {
        printf(RED "\n%d test(s) failed.\n" RESET, failures);
        return 1;
    }
}
