/**
 * @file vulkan_denylist.cpp
 * @brief Vulkan driver denylist implementation
 *
 * Maintains a static table of known-broken Vulkan drivers identified
 * by substring matching against the device description string returned
 * by ggml_backend_vk_get_device_description().
 *
 * Sources:
 * - Adreno 5xx: llama.cpp #16881 (gibberish output from compute shaders)
 * - PowerVR: insufficient Vulkan compute shader support for ggml workloads
 */

#include "vulkan_denylist.h"
#include <cstring>

struct DenylistEntry {
    const char* substring;  // Matched against device description
    const char* reason;     // Human-readable reason for logging
};

// Populated from community reports and llama.cpp issue tracker.
// Add entries as broken drivers are discovered during testing.
static const DenylistEntry VULKAN_DENYLIST[] = {
    // Adreno 5xx series: known gibberish output (llama.cpp #16881)
    {"Adreno (TM) 5", "Adreno 500 series: incorrect compute results"},

    // PowerVR: very limited Vulkan compute shader support
    {"PowerVR", "PowerVR: insufficient Vulkan compute support"},

    // Sentinel
    {nullptr, nullptr}
};

bool ev_vulkan_is_denied(const char* device_description) {
    if (!device_description) return false;

    for (int i = 0; VULKAN_DENYLIST[i].substring != nullptr; i++) {
        if (strstr(device_description, VULKAN_DENYLIST[i].substring)) {
            return true;
        }
    }
    return false;
}

const char* ev_vulkan_deny_reason(const char* device_description) {
    if (!device_description) return nullptr;

    for (int i = 0; VULKAN_DENYLIST[i].substring != nullptr; i++) {
        if (strstr(device_description, VULKAN_DENYLIST[i].substring)) {
            return VULKAN_DENYLIST[i].reason;
        }
    }
    return nullptr;
}
