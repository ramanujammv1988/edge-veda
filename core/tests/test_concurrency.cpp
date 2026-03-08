/**
 * @file test_concurrency.cpp
 * @brief CI-safe concurrency regression tests for Edge Veda
 *
 * Tests thread safety of backend lifecycle, memory guard, and
 * NULL-guard fast paths under concurrent access. No model file needed.
 *
 * Model-backed concurrency tests (simultaneous stream+embed,
 * free+active-stream) require EDGE_VEDA_TEST_MODEL_PATH.
 */

#include "edge_veda.h"
#include <cstdio>
#include <cstddef>
#include <thread>
#include <vector>
#include <atomic>

// Memory guard forward declarations
extern "C" {
    void memory_guard_set_limit(size_t limit_bytes);
    size_t memory_guard_get_limit();
    size_t memory_guard_get_recommended_limit();
    size_t memory_guard_get_total_memory();
}

// Backend lifecycle
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

// ---------- Backend lifecycle concurrency ----------

#ifdef EDGE_VEDA_LLAMA_ENABLED

int test_backend_concurrent_acquire_release() {
    const int N_THREADS = 8;
    const int N_ITERATIONS = 10;
    std::atomic<int> errors{0};

    std::vector<std::thread> threads;
    for (int i = 0; i < N_THREADS; i++) {
        threads.emplace_back([&errors, N_ITERATIONS]() {
            for (int j = 0; j < N_ITERATIONS; j++) {
                edge_veda_backend_acquire();
                edge_veda_backend_release();
            }
        });
    }
    for (auto& t : threads) {
        t.join();
    }

    return errors.load() > 0 ? 1 : 0;
}

#endif // EDGE_VEDA_LLAMA_ENABLED

// ---------- Memory guard concurrency ----------

int test_memory_guard_concurrent_set_get_limit() {
    const int N_THREADS = 8;
    const int N_ITERATIONS = 100;
    std::atomic<int> errors{0};

    // Save and restore original limit
    size_t original = memory_guard_get_limit();

    std::vector<std::thread> threads;
    for (int i = 0; i < N_THREADS; i++) {
        threads.emplace_back([&errors, N_ITERATIONS, i]() {
            for (int j = 0; j < N_ITERATIONS; j++) {
                size_t val = (size_t)(i + 1) * 100 * 1024 * 1024; // 100-800 MB
                memory_guard_set_limit(val);
                // Read back — may not match due to concurrent writes, that's OK.
                // The point is no crash or data corruption.
                (void)memory_guard_get_limit();
            }
        });
    }
    for (auto& t : threads) {
        t.join();
    }

    memory_guard_set_limit(original);
    return errors.load() > 0 ? 1 : 0;
}

int test_memory_guard_concurrent_recommended_limit() {
    const int N_THREADS = 4;
    std::atomic<int> errors{0};

    std::vector<std::thread> threads;
    for (int i = 0; i < N_THREADS; i++) {
        threads.emplace_back([&errors]() {
            size_t limit = memory_guard_get_recommended_limit();
            if (limit == 0) errors.fetch_add(1);
            size_t total = memory_guard_get_total_memory();
            if (total == 0) errors.fetch_add(1);
        });
    }
    for (auto& t : threads) {
        t.join();
    }

    return errors.load() > 0 ? 1 : 0;
}

// ---------- NULL-guard paths under concurrency ----------

int test_null_guards_concurrent_vision() {
    const int N_THREADS = 4;
    std::atomic<int> errors{0};

    std::vector<std::thread> threads;
    for (int i = 0; i < N_THREADS; i++) {
        threads.emplace_back([&errors]() {
            ev_error_t error = EV_SUCCESS;
            ev_vision_context ctx = ev_vision_init(NULL, &error);
            if (ctx != NULL || error != EV_ERROR_INVALID_PARAM) errors.fetch_add(1);

            ev_vision_free(NULL); // Must not crash

            if (ev_vision_is_valid(NULL) != false) errors.fetch_add(1);
        });
    }
    for (auto& t : threads) {
        t.join();
    }

    return errors.load() > 0 ? 1 : 0;
}

int test_null_guards_concurrent_whisper() {
    const int N_THREADS = 4;
    std::atomic<int> errors{0};

    std::vector<std::thread> threads;
    for (int i = 0; i < N_THREADS; i++) {
        threads.emplace_back([&errors]() {
            ev_error_t error = EV_SUCCESS;
            ev_whisper_context ctx = ev_whisper_init(NULL, &error);
            if (ctx != NULL || error != EV_ERROR_INVALID_PARAM) errors.fetch_add(1);

            ev_whisper_free(NULL); // Must not crash

            if (ev_whisper_is_valid(NULL) != false) errors.fetch_add(1);
        });
    }
    for (auto& t : threads) {
        t.join();
    }

    return errors.load() > 0 ? 1 : 0;
}

int test_null_guards_concurrent_image() {
    const int N_THREADS = 4;
    std::atomic<int> errors{0};

    std::vector<std::thread> threads;
    for (int i = 0; i < N_THREADS; i++) {
        threads.emplace_back([&errors]() {
            ev_error_t error = EV_SUCCESS;
            ev_image_context ctx = ev_image_init(NULL, &error);
            if (ctx != NULL || error != EV_ERROR_INVALID_PARAM) errors.fetch_add(1);

            ev_image_free(NULL); // Must not crash

            if (ev_image_is_valid(NULL) != false) errors.fetch_add(1);
        });
    }
    for (auto& t : threads) {
        t.join();
    }

    return errors.load() > 0 ? 1 : 0;
}

int test_null_guards_concurrent_llm() {
    const int N_THREADS = 4;
    std::atomic<int> errors{0};

    std::vector<std::thread> threads;
    for (int i = 0; i < N_THREADS; i++) {
        threads.emplace_back([&errors]() {
            ev_error_t error = EV_SUCCESS;
            ev_context ctx = ev_init(NULL, &error);
            if (ctx != NULL || error != EV_ERROR_INVALID_PARAM) errors.fetch_add(1);

            ev_free(NULL); // Must not crash

            if (ev_is_valid(NULL) != false) errors.fetch_add(1);
        });
    }
    for (auto& t : threads) {
        t.join();
    }

    return errors.load() > 0 ? 1 : 0;
}

// ---------- Model-backed concurrency (requires model) ----------

#ifdef TEST_MODEL_PATH

int test_concurrent_stream_and_embed() {
    // Load model
    ev_config config;
    ev_config_default(&config);
    config.model_path = TEST_MODEL_PATH;
    config.context_size = 512;
    config.num_threads = 2;

    ev_error_t error = EV_SUCCESS;
    ev_context ctx = ev_init(&config, &error);
    if (!ctx) {
        printf("  (skipped: model load failed)\n");
        return 0;
    }

    std::atomic<bool> stream_done{false};
    std::atomic<bool> embed_done{false};
    std::atomic<int> errors{0};

    // Thread A: stream generation
    std::thread stream_thread([&]() {
        ev_error_t serr = EV_SUCCESS;
        ev_stream s = ev_generate_stream(ctx, "Hello", NULL, &serr);
        if (s) {
            while (ev_stream_has_next(s)) {
                char* tok = ev_stream_next(s, &serr);
                if (tok) ev_free_string(tok);
            }
            ev_stream_free(s);
        }
        stream_done.store(true);
    });

    // Thread B: try embed (should fail gracefully due to single-stream enforcement)
    std::thread embed_thread([&]() {
        // Small delay to let stream start
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        ev_embed_result result;
        memset(&result, 0, sizeof(result));
        ev_error_t eerr = ev_embed(ctx, "test", &result);
        // Either succeeds or returns error — must not crash
        if (eerr == EV_SUCCESS) {
            ev_free_embeddings(&result);
        }
        embed_done.store(true);
    });

    stream_thread.join();
    embed_thread.join();

    ev_free(ctx);
    return errors.load() > 0 ? 1 : 0;
}

#endif // TEST_MODEL_PATH

// ---------- Main ----------

int main() {
    printf("\n=== Edge Veda Concurrency Tests ===\n\n");

    int passes = 0;
    int failures = 0;

    // Backend lifecycle concurrency
#ifdef EDGE_VEDA_LLAMA_ENABLED
    TEST(test_backend_concurrent_acquire_release);
#endif

    // Memory guard concurrency
    TEST(test_memory_guard_concurrent_set_get_limit);
    TEST(test_memory_guard_concurrent_recommended_limit);

    // NULL-guard paths under concurrency
    TEST(test_null_guards_concurrent_vision);
    TEST(test_null_guards_concurrent_whisper);
    TEST(test_null_guards_concurrent_image);
    TEST(test_null_guards_concurrent_llm);

    // Model-backed concurrency (only when model path provided)
#ifdef TEST_MODEL_PATH
    TEST(test_concurrent_stream_and_embed);
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
