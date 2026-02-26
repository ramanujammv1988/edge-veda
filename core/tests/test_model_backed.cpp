/**
 * @file test_model_backed.cpp
 * @brief Model-backed C API tests for Edge Veda
 *
 * Requires a GGUF model file. Path provided at compile time via
 * -DTEST_MODEL_PATH="...". Exercises stream lifecycle, single-stream
 * enforcement, embed operations, and cross-API interactions.
 *
 * Deterministic: temperature=0 (greedy argmax).
 */

#include "edge_veda.h"
#include <cstdio>
#include <cstring>
#include <cmath>

#ifndef TEST_MODEL_PATH
#error "TEST_MODEL_PATH must be defined at compile time"
#endif

// ANSI colors for output
#define GREEN  "\033[32m"
#define RED    "\033[31m"
#define YELLOW "\033[33m"
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

// Shared context — loaded once, reused across tests.
static ev_context g_ctx = nullptr;

// Helper: create deterministic generation params.
static ev_generation_params greedy_params(int max_tokens = 10) {
    ev_generation_params p;
    ev_generation_params_default(&p);
    p.max_tokens = max_tokens;
    p.temperature = 0.0f;
    p.top_k = 1;
    return p;
}

// Helper: drain a stream, counting tokens. Frees each token string.
static int drain_stream(ev_stream s) {
    int count = 0;
    while (true) {
        ev_error_t err = EV_SUCCESS;
        char* tok = ev_stream_next(s, &err);
        if (!tok) break;
        ev_free_string(tok);
        count++;
    }
    return count;
}

// ===== Phase 1b: Stream lifecycle tests =====

int test_stream_basic_lifecycle() {
    ev_generation_params p = greedy_params(5);
    ev_error_t err = EV_SUCCESS;
    ev_stream s = ev_generate_stream(g_ctx, "Hello", &p, &err);
    if (!s) return 1;
    if (err != EV_SUCCESS) return 1;

    int tokens = drain_stream(s);
    if (tokens < 1) return 1;

    ev_stream_free(s);

    // Context should still be valid after stream lifecycle
    if (!ev_is_valid(g_ctx)) return 1;
    return 0;
}

int test_single_stream_enforcement() {
    ev_generation_params p = greedy_params(20);
    ev_error_t err = EV_SUCCESS;

    // Open first stream
    ev_stream s1 = ev_generate_stream(g_ctx, "Once", &p, &err);
    if (!s1) return 1;

    // Second stream on same context must fail
    ev_error_t err2 = EV_SUCCESS;
    ev_stream s2 = ev_generate_stream(g_ctx, "Twice", &p, &err2);
    if (s2 != nullptr) return 1;
    if (err2 != EV_ERROR_CONTEXT_INVALID) return 1;

    // Free first stream
    drain_stream(s1);
    ev_stream_free(s1);

    // Now a new stream should succeed
    ev_error_t err3 = EV_SUCCESS;
    ev_stream s3 = ev_generate_stream(g_ctx, "Again", &p, &err3);
    if (!s3) return 1;

    drain_stream(s3);
    ev_stream_free(s3);
    return 0;
}

int test_generate_blocked_by_active_stream() {
    ev_generation_params p = greedy_params(20);
    ev_error_t err = EV_SUCCESS;

    // Open a stream
    ev_stream s = ev_generate_stream(g_ctx, "Block", &p, &err);
    if (!s) return 1;

    // ev_generate on same context must fail
    char* output = nullptr;
    ev_error_t gen_err = ev_generate(g_ctx, "Test", &p, &output);
    if (gen_err != EV_ERROR_CONTEXT_INVALID) return 1;
    if (output != nullptr) return 1;

    // Clean up stream
    drain_stream(s);
    ev_stream_free(s);

    // Now ev_generate should succeed
    ev_generation_params p2 = greedy_params(5);
    char* output2 = nullptr;
    ev_error_t gen_err2 = ev_generate(g_ctx, "Test", &p2, &output2);
    if (gen_err2 != EV_SUCCESS) return 1;
    if (!output2 || strlen(output2) == 0) return 1;
    ev_free_string(output2);
    return 0;
}

int test_stream_cancel() {
    ev_generation_params p = greedy_params(100);
    ev_error_t err = EV_SUCCESS;

    ev_stream s = ev_generate_stream(g_ctx, "Cancel me", &p, &err);
    if (!s) return 1;

    // Cancel immediately
    ev_stream_cancel(s);

    // Next call should return NULL with STREAM_ENDED
    ev_error_t next_err = EV_SUCCESS;
    char* tok = ev_stream_next(s, &next_err);
    if (tok != nullptr) {
        ev_free_string(tok);
        // Cancel may not be immediate if first call evaluates prompt.
        // Drain the rest — cancel should stop it early.
        drain_stream(s);
    }
    // After drain, stream should be ended
    if (ev_stream_has_next(s)) return 1;

    ev_stream_free(s);
    return 0;
}

int test_stream_has_next() {
    ev_generation_params p = greedy_params(3);
    ev_error_t err = EV_SUCCESS;

    ev_stream s = ev_generate_stream(g_ctx, "Count", &p, &err);
    if (!s) return 1;

    // Before exhausting, has_next should be true
    if (!ev_stream_has_next(s)) return 1;

    // Exhaust the stream
    drain_stream(s);

    // After exhausting, has_next should be false
    if (ev_stream_has_next(s)) return 1;

    ev_stream_free(s);
    return 0;
}

int test_generate_after_stream_complete() {
    // Full stream lifecycle, then ev_generate — verifies active_stream_count is 0
    ev_generation_params p = greedy_params(3);
    ev_error_t err = EV_SUCCESS;

    ev_stream s = ev_generate_stream(g_ctx, "First", &p, &err);
    if (!s) return 1;
    drain_stream(s);
    ev_stream_free(s);

    // Sync generate should work now
    ev_generation_params p2 = greedy_params(5);
    char* output = nullptr;
    ev_error_t gen_err = ev_generate(g_ctx, "Second", &p2, &output);
    if (gen_err != EV_SUCCESS) return 1;
    if (!output || strlen(output) == 0) return 1;
    ev_free_string(output);
    return 0;
}

int test_stream_free_then_context_valid() {
    // Verify context remains fully usable after stream create → drain → free cycle.
    ev_generation_params p = greedy_params(3);
    ev_error_t err = EV_SUCCESS;

    ev_stream s = ev_generate_stream(g_ctx, "Cleanup", &p, &err);
    if (!s) return 1;
    drain_stream(s);
    ev_stream_free(s);

    // Context should be valid and active_stream_count back to 0
    if (!ev_is_valid(g_ctx)) return 1;

    // Prove context is truly reusable by running a sync generate
    ev_generation_params p2 = greedy_params(3);
    char* output = nullptr;
    ev_error_t gen_err = ev_generate(g_ctx, "Reuse", &p2, &output);
    if (gen_err != EV_SUCCESS) return 1;
    if (!output || strlen(output) == 0) return 1;
    ev_free_string(output);
    return 0;
}

// ===== Phase 2: Embeddings tests =====

int test_embed_basic() {
    ev_embed_result result;
    memset(&result, 0, sizeof(result));

    ev_error_t err = ev_embed(g_ctx, "Hello world", &result);
    if (err != EV_SUCCESS) return 1;
    if (result.dimensions <= 0) return 1;
    if (result.token_count <= 0) return 1;
    if (!result.embeddings) return 1;

    // L2 norm should be ~1.0 (embeddings are L2-normalized in engine.cpp)
    double sum_sq = 0.0;
    for (int i = 0; i < result.dimensions; i++) {
        sum_sq += (double)result.embeddings[i] * (double)result.embeddings[i];
    }
    double l2 = sqrt(sum_sq);
    if (fabs(l2 - 1.0) > 0.01) return 1;

    ev_free_embeddings(&result);
    return 0;
}

int test_embed_repeat_calls() {
    ev_embed_result r1, r2;
    memset(&r1, 0, sizeof(r1));
    memset(&r2, 0, sizeof(r2));

    ev_error_t err1 = ev_embed(g_ctx, "deterministic", &r1);
    ev_error_t err2 = ev_embed(g_ctx, "deterministic", &r2);
    if (err1 != EV_SUCCESS || err2 != EV_SUCCESS) return 1;
    if (r1.dimensions != r2.dimensions) return 1;

    // Same text → same embeddings (deterministic forward pass)
    for (int i = 0; i < r1.dimensions; i++) {
        if (fabs(r1.embeddings[i] - r2.embeddings[i]) > 1e-6f) return 1;
    }

    ev_free_embeddings(&r1);
    ev_free_embeddings(&r2);
    return 0;
}

int test_embed_different_texts() {
    ev_embed_result r1, r2;
    memset(&r1, 0, sizeof(r1));
    memset(&r2, 0, sizeof(r2));

    ev_error_t err1 = ev_embed(g_ctx, "cat", &r1);
    ev_error_t err2 = ev_embed(g_ctx, "supercalifragilistic", &r2);
    if (err1 != EV_SUCCESS || err2 != EV_SUCCESS) return 1;
    if (r1.dimensions != r2.dimensions) return 1;

    // Different texts → vectors should differ
    bool all_same = true;
    for (int i = 0; i < r1.dimensions; i++) {
        if (fabs(r1.embeddings[i] - r2.embeddings[i]) > 1e-6f) {
            all_same = false;
            break;
        }
    }
    if (all_same) return 1;

    ev_free_embeddings(&r1);
    ev_free_embeddings(&r2);
    return 0;
}

int test_embed_after_generate() {
    // ev_generate clears KV cache on llama_ctx, but embed uses
    // a separate embed_ctx — should still work.
    ev_generation_params p = greedy_params(5);
    char* output = nullptr;
    ev_error_t gen_err = ev_generate(g_ctx, "Generate first", &p, &output);
    if (gen_err != EV_SUCCESS) return 1;
    ev_free_string(output);

    // Embed should succeed (separate context)
    ev_embed_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t emb_err = ev_embed(g_ctx, "Embed after", &result);
    if (emb_err != EV_SUCCESS) return 1;
    if (result.dimensions <= 0) return 1;

    ev_free_embeddings(&result);
    return 0;
}

int test_embed_memory_stats() {
    // Get memory usage — context_bytes should be > 0 after model load
    ev_memory_stats stats;
    memset(&stats, 0, sizeof(stats));
    ev_error_t err = ev_get_memory_usage(g_ctx, &stats);
    if (err != EV_SUCCESS) return 1;

    // Model should have non-zero memory usage
    if (stats.model_bytes == 0) return 1;

    // Trigger embed to lazy-init embed_ctx (may already be initialized
    // by prior tests — that's fine, we just verify stats work)
    ev_embed_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t emb_err = ev_embed(g_ctx, "stats check", &result);
    if (emb_err != EV_SUCCESS) return 1;
    ev_free_embeddings(&result);

    // Re-check memory — embed_ctx should contribute to context_bytes
    ev_memory_stats stats2;
    memset(&stats2, 0, sizeof(stats2));
    ev_error_t err2 = ev_get_memory_usage(g_ctx, &stats2);
    if (err2 != EV_SUCCESS) return 1;
    if (stats2.model_bytes == 0) return 1;
    if (stats2.context_bytes == 0) return 1;

    return 0;
}

// ===== Main =====

int main() {
    printf("\n=== Edge Veda Model-Backed Tests ===\n");
    printf("Model: %s\n\n", TEST_MODEL_PATH);

    // Load model
    ev_config config;
    ev_config_default(&config);
    config.model_path = TEST_MODEL_PATH;
    config.context_size = 512;
    config.gpu_layers = 0;   // CPU only in CI
    config.num_threads = 2;
    config.use_mmap = true;

    ev_error_t init_err = EV_SUCCESS;
    g_ctx = ev_init(&config, &init_err);
    if (!g_ctx) {
        printf(RED "[FATAL]" RESET " Failed to load model: %s (error %d)\n",
               ev_error_string(init_err), init_err);
        return 1;
    }
    printf(GREEN "[OK]" RESET " Model loaded\n\n");

    int passes = 0;
    int failures = 0;

    // Phase 1b: Stream lifecycle
    printf("--- Stream lifecycle ---\n");
    TEST(test_stream_basic_lifecycle);
    TEST(test_single_stream_enforcement);
    TEST(test_generate_blocked_by_active_stream);
    TEST(test_stream_cancel);
    TEST(test_stream_has_next);
    TEST(test_generate_after_stream_complete);
    TEST(test_stream_free_then_context_valid);

    // Phase 2: Embeddings
    printf("\n--- Embeddings ---\n");
    TEST(test_embed_basic);
    TEST(test_embed_repeat_calls);
    TEST(test_embed_different_texts);
    TEST(test_embed_after_generate);
    TEST(test_embed_memory_stats);

    // Cleanup
    ev_free(g_ctx);

    // Summary
    printf("\n=== Test Summary ===\n");
    printf("Passed: %d\n", passes);
    printf("Failed: %d\n", failures);

    if (failures == 0) {
        printf(GREEN "\nAll %d tests passed!\n" RESET, passes);
        return 0;
    } else {
        printf(RED "\n%d test(s) failed.\n" RESET, failures);
        return 1;
    }
}
