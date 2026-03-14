/**
 * @file vulkan_denylist.h
 * @brief Vulkan driver denylist for known-broken GPU drivers
 *
 * Blocks GPU drivers with documented compute shader bugs or
 * insufficient Vulkan support. Checked during runtime backend
 * detection so that denied devices fall back to CPU silently.
 */

#ifndef EDGE_VEDA_VULKAN_DENYLIST_H
#define EDGE_VEDA_VULKAN_DENYLIST_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Check if a Vulkan device is on the denylist
 * @param device_description Device description string from ggml_backend_vk_get_device_description
 * @return true if the device is denied (should not be used), false if allowed
 */
bool ev_vulkan_is_denied(const char* device_description);

/**
 * @brief Get the denial reason for a Vulkan device
 * @param device_description Device description string
 * @return Reason string if denied, nullptr if device is allowed
 */
const char* ev_vulkan_deny_reason(const char* device_description);

#ifdef __cplusplus
}
#endif

#endif /* EDGE_VEDA_VULKAN_DENYLIST_H */
