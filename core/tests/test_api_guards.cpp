/**
 * @file test_api_guards.cpp
 * @brief CI-safe NULL-path guard tests for the Edge Veda C API
 *
 * Exercises every NULL-guard path in the public C API without requiring
 * a model file. All tests are CI-safe and run in seconds.
 *
 * Follows the same print_pass/print_fail pattern as test_inference.cpp.
 */

#include "edge_veda.h"
#include <cstdio>
#include <cstring>

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

// Each test function returns 0 on success, 1 on failure.

#define TEST(name) do { \
    int _r = name(); \
    if (_r == 0) { passes++; print_pass(#name); } \
    else { failures++; print_fail(#name, "assertion failed"); } \
} while(0)

// ---------- Streaming generation guards ----------

int test_ev_generate_stream_null_ctx() {
    ev_error_t error = EV_SUCCESS;
    ev_stream s = ev_generate_stream(NULL, "hello", NULL, &error);
    if (s != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_generate_stream_null_prompt() {
    // ctx is also NULL, so the NULL-ctx guard triggers first
    ev_error_t error = EV_SUCCESS;
    ev_stream s = ev_generate_stream(NULL, NULL, NULL, &error);
    if (s != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_stream_free_null() {
    // Must not crash
    ev_stream_free(NULL);
    return 0;
}

int test_ev_stream_next_null() {
    ev_error_t error = EV_SUCCESS;
    char* token = ev_stream_next(NULL, &error);
    if (token != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

// ---------- Context lifecycle guards ----------

int test_ev_free_null() {
    // Must not crash
    ev_free(NULL);
    return 0;
}

// ---------- Embeddings guards ----------

int test_ev_embed_null_ctx() {
    ev_embed_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t err = ev_embed(NULL, "hello", &result);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_embed_null_text() {
    ev_embed_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t err = ev_embed(NULL, NULL, &result);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_embed_null_result() {
    ev_error_t err = ev_embed(NULL, "hello", NULL);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

// ---------- Single-shot generation guards ----------

int test_ev_generate_null_ctx() {
    char* output = NULL;
    ev_error_t err = ev_generate(NULL, "hello", NULL, &output);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_generate_null_prompt() {
    char* output = NULL;
    ev_error_t err = ev_generate(NULL, NULL, NULL, &output);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_generate_null_output() {
    ev_error_t err = ev_generate(NULL, "hello", NULL, NULL);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

// ---------- Context validity guard ----------

int test_ev_is_valid_null() {
    if (ev_is_valid(NULL) != false) return 1;
    return 0;
}

// ---------- Model info guard ----------

int test_ev_get_model_info_null() {
    ev_model_info info;
    memset(&info, 0, sizeof(info));
    ev_error_t err = ev_get_model_info(NULL, &info);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

// ---------- Memory management guards ----------

int test_ev_get_memory_usage_null() {
    ev_memory_stats stats;
    memset(&stats, 0, sizeof(stats));
    ev_error_t err = ev_get_memory_usage(NULL, &stats);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_reset_null() {
    ev_error_t err = ev_reset(NULL);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_set_memory_limit_null() {
    ev_error_t err = ev_set_memory_limit(NULL, 1024);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

// ---------- Stream utility guards ----------

int test_ev_stream_has_next_null() {
    if (ev_stream_has_next(NULL) != false) return 1;
    return 0;
}

int test_ev_stream_cancel_null() {
    // Must not crash
    ev_stream_cancel(NULL);
    return 0;
}

// ---------- Error / utility guards ----------

int test_ev_get_last_error_null() {
    const char* msg = ev_get_last_error(NULL);
    if (msg == NULL) return 1;
    // Should return "Invalid context"
    if (strlen(msg) == 0) return 1;
    return 0;
}

int test_ev_stream_get_token_info_null() {
    ev_stream_token_info info;
    memset(&info, 0, sizeof(info));
    ev_error_t err = ev_stream_get_token_info(NULL, &info);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

// ---------- Init guards ----------

int test_ev_init_null_config() {
    ev_error_t error = EV_SUCCESS;
    ev_context ctx = ev_init(NULL, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_init_null_model_path() {
    ev_config config;
    ev_config_default(&config);
    // model_path is NULL after ev_config_default
    ev_error_t error = EV_SUCCESS;
    ev_context ctx = ev_init(&config, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

// ---------- Free helpers guards ----------

int test_ev_free_string_null() {
    // Must not crash
    ev_free_string(NULL);
    return 0;
}

int test_ev_free_embeddings_null() {
    // NULL pointer -- must not crash
    ev_free_embeddings(NULL);
    // Zeroed result with embeddings=NULL -- must not crash
    ev_embed_result zeroed;
    memset(&zeroed, 0, sizeof(zeroed));
    ev_free_embeddings(&zeroed);
    return 0;
}

// ---------- Version / error string ----------

int test_ev_version() {
    const char* v = ev_version();
    if (v == NULL) return 1;
    if (strlen(v) == 0) return 1;
    return 0;
}

int test_ev_error_string() {
    const char* s1 = ev_error_string(EV_SUCCESS);
    const char* s2 = ev_error_string(EV_ERROR_INVALID_PARAM);
    if (s1 == NULL || s2 == NULL) return 1;
    return 0;
}

// ---------- Config default guards ----------

int test_ev_config_default_null() {
    // Must not crash
    ev_config_default(NULL);
    return 0;
}

int test_ev_generation_params_default_null() {
    // Must not crash
    ev_generation_params_default(NULL);
    return 0;
}

// ---------- Vision API guards ----------

int test_ev_vision_init_null_config() {
    ev_error_t error = EV_SUCCESS;
    ev_vision_context ctx = ev_vision_init(NULL, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_init_null_model_path() {
    ev_vision_config config;
    ev_vision_config_default(&config);
    // model_path is NULL after default, mmproj_path is also NULL
    ev_error_t error = EV_SUCCESS;
    ev_vision_context ctx = ev_vision_init(&config, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_init_null_mmproj_path() {
    ev_vision_config config;
    ev_vision_config_default(&config);
    config.model_path = "/nonexistent/model.gguf";
    // mmproj_path is still NULL
    ev_error_t error = EV_SUCCESS;
    ev_vision_context ctx = ev_vision_init(&config, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_describe_null_ctx() {
    unsigned char dummy_image[3] = {0, 0, 0};
    char* output = NULL;
    ev_error_t err = ev_vision_describe(NULL, dummy_image, 1, 1, "describe", NULL, &output);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_describe_null_image() {
    char* output = NULL;
    ev_error_t err = ev_vision_describe(NULL, NULL, 1, 1, "describe", NULL, &output);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_describe_null_prompt() {
    unsigned char dummy_image[3] = {0, 0, 0};
    char* output = NULL;
    ev_error_t err = ev_vision_describe(NULL, dummy_image, 1, 1, NULL, NULL, &output);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_describe_null_output() {
    unsigned char dummy_image[3] = {0, 0, 0};
    ev_error_t err = ev_vision_describe(NULL, dummy_image, 1, 1, "describe", NULL, NULL);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_free_null() {
    // Must not crash
    ev_vision_free(NULL);
    return 0;
}

int test_ev_vision_is_valid_null() {
    if (ev_vision_is_valid(NULL) != false) return 1;
    return 0;
}

int test_ev_vision_config_default_null() {
    // Must not crash
    ev_vision_config_default(NULL);
    return 0;
}

int test_ev_vision_get_last_timings_null_ctx() {
    ev_timings_data timings;
    ev_error_t err = ev_vision_get_last_timings(NULL, &timings);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_get_last_timings_null_both() {
    ev_error_t err = ev_vision_get_last_timings(NULL, NULL);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

// ---------- Whisper API guards ----------

int test_ev_whisper_init_null_config() {
    ev_error_t error = EV_SUCCESS;
    ev_whisper_context ctx = ev_whisper_init(NULL, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_whisper_init_null_model_path() {
    ev_whisper_config config;
    ev_whisper_config_default(&config);
    // model_path is NULL after default
    ev_error_t error = EV_SUCCESS;
    ev_whisper_context ctx = ev_whisper_init(&config, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_whisper_transcribe_null_ctx() {
    float dummy_pcm[16] = {0};
    ev_whisper_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t err = ev_whisper_transcribe(NULL, dummy_pcm, 16, NULL, &result);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_whisper_transcribe_null_pcm() {
    ev_whisper_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t err = ev_whisper_transcribe(NULL, NULL, 16, NULL, &result);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_whisper_transcribe_null_result() {
    float dummy_pcm[16] = {0};
    ev_error_t err = ev_whisper_transcribe(NULL, dummy_pcm, 16, NULL, NULL);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_whisper_transcribe_zero_samples() {
    float dummy_pcm[16] = {0};
    ev_whisper_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t err = ev_whisper_transcribe(NULL, dummy_pcm, 0, NULL, &result);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_whisper_free_null() {
    // Must not crash
    ev_whisper_free(NULL);
    return 0;
}

int test_ev_whisper_is_valid_null() {
    if (ev_whisper_is_valid(NULL) != false) return 1;
    return 0;
}

int test_ev_whisper_config_default_null() {
    // Must not crash
    ev_whisper_config_default(NULL);
    return 0;
}

int test_ev_whisper_free_result_null() {
    // Must not crash
    ev_whisper_free_result(NULL);
    return 0;
}

int test_ev_whisper_free_result_zeroed() {
    ev_whisper_result zeroed;
    memset(&zeroed, 0, sizeof(zeroed));
    // Must not crash
    ev_whisper_free_result(&zeroed);
    return 0;
}

// ---------- Image Gen API guards ----------

int test_ev_image_init_null_config() {
    ev_error_t error = EV_SUCCESS;
    ev_image_context ctx = ev_image_init(NULL, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_image_init_null_model_path() {
    ev_image_config config;
    ev_image_config_default(&config);
    // model_path is NULL after default
    ev_error_t error = EV_SUCCESS;
    ev_image_context ctx = ev_image_init(&config, &error);
    if (ctx != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_image_generate_null_ctx() {
    ev_image_gen_params params;
    ev_image_gen_params_default(&params);
    params.prompt = "test";
    ev_image_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t err = ev_image_generate(NULL, &params, &result);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_image_generate_null_params() {
    ev_image_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t err = ev_image_generate(NULL, NULL, &result);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_image_generate_null_result() {
    ev_image_gen_params params;
    ev_image_gen_params_default(&params);
    params.prompt = "test";
    ev_error_t err = ev_image_generate(NULL, &params, NULL);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_image_generate_null_prompt() {
    ev_image_gen_params params;
    ev_image_gen_params_default(&params);
    // params.prompt is NULL after default
    ev_image_result result;
    memset(&result, 0, sizeof(result));
    ev_error_t err = ev_image_generate(NULL, &params, &result);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_image_free_null() {
    // Must not crash
    ev_image_free(NULL);
    return 0;
}

int test_ev_image_is_valid_null() {
    if (ev_image_is_valid(NULL) != false) return 1;
    return 0;
}

int test_ev_image_free_result_null() {
    // Must not crash
    ev_image_free_result(NULL);
    return 0;
}

int test_ev_image_free_result_zeroed() {
    ev_image_result zeroed;
    memset(&zeroed, 0, sizeof(zeroed));
    // Must not crash
    ev_image_free_result(&zeroed);
    return 0;
}

int test_ev_image_config_default_null() {
    // Must not crash
    ev_image_config_default(NULL);
    return 0;
}

int test_ev_image_gen_params_default_null() {
    // Must not crash
    ev_image_gen_params_default(NULL);
    return 0;
}

int test_ev_image_set_progress_callback_null_ctx() {
    // Must not crash
    ev_image_set_progress_callback(NULL, NULL, NULL);
    return 0;
}

int test_ev_image_cancel_null() {
    // Must not crash
    ev_image_cancel(NULL);
    return 0;
}

// ---------- Vision Streaming API guards ----------

int test_ev_vision_describe_stream_null_ctx() {
    unsigned char pixel = 0;
    ev_error_t error = EV_SUCCESS;
    ev_vision_stream s = ev_vision_describe_stream(NULL, &pixel, 1, 1, "test", NULL, &error);
    if (s != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_describe_stream_null_image() {
    ev_error_t error = EV_SUCCESS;
    ev_vision_stream s = ev_vision_describe_stream(NULL, NULL, 1, 1, "test", NULL, &error);
    if (s != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_describe_stream_null_prompt() {
    unsigned char pixel = 0;
    ev_error_t error = EV_SUCCESS;
    ev_vision_stream s = ev_vision_describe_stream(NULL, &pixel, 1, 1, NULL, NULL, &error);
    if (s != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_stream_next_null() {
    ev_error_t error = EV_SUCCESS;
    char* token = ev_vision_stream_next(NULL, &error);
    if (token != NULL) return 1;
    if (error != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}

int test_ev_vision_stream_has_next_null() {
    if (ev_vision_stream_has_next(NULL) != false) return 1;
    return 0;
}

int test_ev_vision_stream_cancel_null() {
    // Must not crash
    ev_vision_stream_cancel(NULL);
    return 0;
}

int test_ev_vision_stream_free_null() {
    // Must not crash
    ev_vision_stream_free(NULL);
    return 0;
}

// ---------- Grammar ownership debug hook (conditional) ----------

#ifdef EDGE_VEDA_TEST_HOOKS
int test_ev_test_stream_grammar_owned_null() {
    bool has_str = true, has_root = true;
    ev_error_t err = ev_test_stream_grammar_owned(NULL, &has_str, &has_root);
    if (err != EV_ERROR_INVALID_PARAM) return 1;
    return 0;
}
#endif

// ---------- Main ----------

int main() {
    printf("\n=== Edge Veda C API Guard Tests ===\n\n");

    int passes = 0;
    int failures = 0;

    // Streaming generation guards
    TEST(test_ev_generate_stream_null_ctx);
    TEST(test_ev_generate_stream_null_prompt);
    TEST(test_ev_stream_free_null);
    TEST(test_ev_stream_next_null);

    // Context lifecycle guards
    TEST(test_ev_free_null);

    // Embeddings guards
    TEST(test_ev_embed_null_ctx);
    TEST(test_ev_embed_null_text);
    TEST(test_ev_embed_null_result);

    // Single-shot generation guards
    TEST(test_ev_generate_null_ctx);
    TEST(test_ev_generate_null_prompt);
    TEST(test_ev_generate_null_output);

    // Context validity guard
    TEST(test_ev_is_valid_null);

    // Model info guard
    TEST(test_ev_get_model_info_null);

    // Memory management guards
    TEST(test_ev_get_memory_usage_null);
    TEST(test_ev_reset_null);
    TEST(test_ev_set_memory_limit_null);

    // Stream utility guards
    TEST(test_ev_stream_has_next_null);
    TEST(test_ev_stream_cancel_null);

    // Error / utility guards
    TEST(test_ev_get_last_error_null);
    TEST(test_ev_stream_get_token_info_null);

    // Init guards
    TEST(test_ev_init_null_config);
    TEST(test_ev_init_null_model_path);

    // Free helpers guards
    TEST(test_ev_free_string_null);
    TEST(test_ev_free_embeddings_null);

    // Version / error string
    TEST(test_ev_version);
    TEST(test_ev_error_string);

    // Config default guards
    TEST(test_ev_config_default_null);
    TEST(test_ev_generation_params_default_null);

    // Vision API guards
    TEST(test_ev_vision_init_null_config);
    TEST(test_ev_vision_init_null_model_path);
    TEST(test_ev_vision_init_null_mmproj_path);
    TEST(test_ev_vision_describe_null_ctx);
    TEST(test_ev_vision_describe_null_image);
    TEST(test_ev_vision_describe_null_prompt);
    TEST(test_ev_vision_describe_null_output);
    TEST(test_ev_vision_free_null);
    TEST(test_ev_vision_is_valid_null);
    TEST(test_ev_vision_config_default_null);
    TEST(test_ev_vision_get_last_timings_null_ctx);
    TEST(test_ev_vision_get_last_timings_null_both);

    // Whisper API guards
    TEST(test_ev_whisper_init_null_config);
    TEST(test_ev_whisper_init_null_model_path);
    TEST(test_ev_whisper_transcribe_null_ctx);
    TEST(test_ev_whisper_transcribe_null_pcm);
    TEST(test_ev_whisper_transcribe_null_result);
    TEST(test_ev_whisper_transcribe_zero_samples);
    TEST(test_ev_whisper_free_null);
    TEST(test_ev_whisper_is_valid_null);
    TEST(test_ev_whisper_config_default_null);
    TEST(test_ev_whisper_free_result_null);
    TEST(test_ev_whisper_free_result_zeroed);

    // Image Gen API guards
    TEST(test_ev_image_init_null_config);
    TEST(test_ev_image_init_null_model_path);
    TEST(test_ev_image_generate_null_ctx);
    TEST(test_ev_image_generate_null_params);
    TEST(test_ev_image_generate_null_result);
    TEST(test_ev_image_generate_null_prompt);
    TEST(test_ev_image_free_null);
    TEST(test_ev_image_is_valid_null);
    TEST(test_ev_image_free_result_null);
    TEST(test_ev_image_free_result_zeroed);
    TEST(test_ev_image_config_default_null);
    TEST(test_ev_image_gen_params_default_null);
    TEST(test_ev_image_set_progress_callback_null_ctx);
    TEST(test_ev_image_cancel_null);

    // Vision Streaming API guards
    TEST(test_ev_vision_describe_stream_null_ctx);
    TEST(test_ev_vision_describe_stream_null_image);
    TEST(test_ev_vision_describe_stream_null_prompt);
    TEST(test_ev_vision_stream_next_null);
    TEST(test_ev_vision_stream_has_next_null);
    TEST(test_ev_vision_stream_cancel_null);
    TEST(test_ev_vision_stream_free_null);

    // Grammar ownership debug hook (only when compiled with EDGE_VEDA_TEST_HOOKS)
#ifdef EDGE_VEDA_TEST_HOOKS
    TEST(test_ev_test_stream_grammar_owned_null);
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
