/**
 * @file test_inference.cpp
 * @brief Smoke test for Edge Veda inference engine
 *
 * Tests: model loading, text generation, memory tracking, cleanup
 * Reports: tokens/sec, time to first token, memory usage
 */

#include "edge_veda.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <string>

// ANSI colors for output
#define GREEN "\033[32m"
#define RED "\033[31m"
#define YELLOW "\033[33m"
#define RESET "\033[0m"

void print_pass(const char* test) {
    printf(GREEN "[PASS]" RESET " %s\n", test);
}

void print_fail(const char* test, const char* reason) {
    printf(RED "[FAIL]" RESET " %s: %s\n", test, reason);
}

void print_info(const char* msg) {
    printf(YELLOW "[INFO]" RESET " %s\n", msg);
}

int main(int argc, char** argv) {
    printf("\n=== Edge Veda Inference Test ===\n\n");

    // Check for model path argument
    if (argc < 2) {
        printf("Usage: %s <model.gguf> [prompt]\n", argv[0]);
        printf("\nExample:\n");
        printf("  %s ./models/llama-3.2-1b-q4_k_m.gguf\n", argv[0]);
        printf("  %s ./models/llama-3.2-1b-q4_k_m.gguf \"What is 2+2?\"\n", argv[0]);
        return 1;
    }

    const char* model_path = argv[1];
    const char* prompt = (argc > 2) ? argv[2] : "Hello, I am a helpful AI assistant.";

    int failures = 0;
    int passes = 0;

    // Test 1: Version
    printf("--- Version Check ---\n");
    const char* version = ev_version();
    if (version && strlen(version) > 0) {
        printf("SDK Version: %s\n", version);
        print_pass("Version check");
        passes++;
    } else {
        print_fail("Version check", "No version string");
        failures++;
    }

    // Test 2: Backend detection
    printf("\n--- Backend Detection ---\n");
    ev_backend_t backend = ev_detect_backend();
    printf("Detected backend: %s\n", ev_backend_name(backend));
    if (ev_is_backend_available(backend)) {
        print_pass("Backend available");
        passes++;
    } else {
        print_fail("Backend available", "No backend available");
        failures++;
    }

    // Test 3: Model loading
    printf("\n--- Model Loading ---\n");
    printf("Model path: %s\n", model_path);

    ev_config config;
    ev_config_default(&config);
    config.model_path = model_path;
    config.backend = EV_BACKEND_AUTO;
    config.context_size = 2048;
    config.gpu_layers = -1;  // All layers to GPU
    config.memory_limit_bytes = 1200 * 1024 * 1024;  // 1.2GB limit

    auto load_start = std::chrono::high_resolution_clock::now();

    ev_error_t error;
    ev_context ctx = ev_init(&config, &error);

    auto load_end = std::chrono::high_resolution_clock::now();
    auto load_ms = std::chrono::duration_cast<std::chrono::milliseconds>(load_end - load_start).count();

    if (ctx && error == EV_SUCCESS) {
        printf("Model loaded in %lld ms\n", (long long)load_ms);
        print_pass("Model loading");
        passes++;
    } else {
        printf("Error: %s (%d)\n", ev_error_string(error), error);
        if (ctx) {
            printf("Last error: %s\n", ev_get_last_error(ctx));
        }
        print_fail("Model loading", ev_error_string(error));
        failures++;
        return 1;  // Can't continue without model
    }

    // Test 4: Model info
    printf("\n--- Model Info ---\n");
    ev_model_info info;
    if (ev_get_model_info(ctx, &info) == EV_SUCCESS) {
        printf("Name: %s\n", info.name ? info.name : "unknown");
        printf("Parameters: %llu\n", (unsigned long long)info.num_parameters);
        printf("Context length: %d\n", info.context_length);
        printf("Embedding dim: %d\n", info.embedding_dim);
        printf("Layers: %d\n", info.num_layers);
        print_pass("Model info");
        passes++;
    } else {
        print_fail("Model info", "Failed to get model info");
        failures++;
    }

    // Test 5: Memory tracking
    printf("\n--- Memory Usage ---\n");
    ev_memory_stats mem_stats;
    if (ev_get_memory_usage(ctx, &mem_stats) == EV_SUCCESS) {
        printf("Current: %.2f MB\n", mem_stats.current_bytes / (1024.0 * 1024.0));
        printf("Model: %.2f MB\n", mem_stats.model_bytes / (1024.0 * 1024.0));
        printf("Context: %.2f MB\n", mem_stats.context_bytes / (1024.0 * 1024.0));
        printf("Limit: %.2f MB\n", mem_stats.limit_bytes / (1024.0 * 1024.0));

        if (mem_stats.current_bytes < mem_stats.limit_bytes || mem_stats.limit_bytes == 0) {
            print_pass("Memory under limit");
            passes++;
        } else {
            print_fail("Memory under limit", "Exceeds configured limit");
            failures++;
        }
    } else {
        print_fail("Memory tracking", "Failed to get memory stats");
        failures++;
    }

    // Test 6: Text generation
    printf("\n--- Text Generation ---\n");
    printf("Prompt: \"%s\"\n\n", prompt);

    ev_generation_params gen_params;
    ev_generation_params_default(&gen_params);
    gen_params.max_tokens = 50;
    gen_params.temperature = 0.7f;
    gen_params.top_p = 0.9f;
    gen_params.top_k = 40;

    char* output = nullptr;

    auto gen_start = std::chrono::high_resolution_clock::now();

    ev_error_t gen_error = ev_generate(ctx, prompt, &gen_params, &output);

    auto gen_end = std::chrono::high_resolution_clock::now();
    auto gen_ms = std::chrono::duration_cast<std::chrono::milliseconds>(gen_end - gen_start).count();

    if (gen_error == EV_SUCCESS && output) {
        printf("Generated text:\n%s\n\n", output);

        // Calculate approximate tokens (rough: ~4 chars per token)
        size_t output_len = strlen(output);
        int approx_tokens = (int)(output_len / 4.0);
        float tokens_per_sec = (gen_ms > 0) ? (approx_tokens * 1000.0f / gen_ms) : 0;

        printf("Generation time: %lld ms\n", (long long)gen_ms);
        printf("Output length: %zu chars\n", output_len);
        printf("Approx tokens: %d\n", approx_tokens);
        printf("Approx speed: %.1f tok/sec\n", tokens_per_sec);

        if (output_len > 0) {
            print_pass("Text generation");
            passes++;
        } else {
            print_fail("Text generation", "Empty output");
            failures++;
        }

        // Check performance target (10 tok/sec)
        if (tokens_per_sec >= 10.0f) {
            print_pass("Performance target (>10 tok/sec)");
            passes++;
        } else {
            char perf_msg[100];
            snprintf(perf_msg, sizeof(perf_msg), "Only %.1f tok/sec (target: >10)", tokens_per_sec);
            print_fail("Performance target", perf_msg);
            failures++;
        }

        ev_free_string(output);
    } else {
        printf("Generation error: %s\n", ev_error_string(gen_error));
        if (ctx) {
            printf("Last error: %s\n", ev_get_last_error(ctx));
        }
        print_fail("Text generation", ev_error_string(gen_error));
        failures++;
    }

    // Test 7: Reset
    printf("\n--- Context Reset ---\n");
    if (ev_reset(ctx) == EV_SUCCESS) {
        print_pass("Context reset");
        passes++;
    } else {
        print_fail("Context reset", "Reset failed");
        failures++;
    }

    // Test 8: Cleanup
    printf("\n--- Cleanup ---\n");
    ev_free(ctx);
    print_pass("Cleanup");
    passes++;

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
