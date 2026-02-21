#include "backend_lifecycle.h"

#ifdef EDGE_VEDA_LLAMA_ENABLED

#include <mutex>
#include <cstdlib>

#include "llama.h"

namespace {

std::mutex g_backend_mutex;
int g_backend_refcount = 0;

void prepare_backend_environment() {
#if defined(__APPLE__) && defined(EDGE_VEDA_METAL_ENABLED)
    // Work around macOS Metal residency-set teardown crashes on some systems.
    // Keep user override if explicitly set in environment.
    if (std::getenv("GGML_METAL_NO_RESIDENCY") == nullptr) {
        setenv("GGML_METAL_NO_RESIDENCY", "1", 0);
    }
#endif
}

}  // namespace

void edge_veda_backend_acquire() {
    std::lock_guard<std::mutex> lock(g_backend_mutex);
    if (g_backend_refcount == 0) {
        prepare_backend_environment();
        llama_backend_init();
    }
    ++g_backend_refcount;
}

void edge_veda_backend_release() {
    std::lock_guard<std::mutex> lock(g_backend_mutex);
    if (g_backend_refcount <= 0) {
        g_backend_refcount = 0;
        return;
    }

    --g_backend_refcount;
    if (g_backend_refcount == 0) {
        llama_backend_free();
    }
}

#endif  // EDGE_VEDA_LLAMA_ENABLED
