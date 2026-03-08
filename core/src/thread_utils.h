#pragma once

/**
 * @file thread_utils.h
 * @brief Platform-aware thread count auto-detection
 *
 * Used by all engine init functions when num_threads=0.
 */

#include <thread>
#include <algorithm>

/**
 * @brief Auto-detect optimal thread count for inference.
 *
 * Uses std::thread::hardware_concurrency() with platform-aware caps:
 * - Android: half of cores, max 4 (big.LITTLE avoids thermal throttling)
 * - iOS/macOS: up to 6 performance cores (Metal handles GPU compute)
 * - Desktop: up to 8
 *
 * @return Recommended thread count (never 0)
 */
static inline unsigned int ev_default_thread_count() {
    unsigned int hw = std::thread::hardware_concurrency();
    if (hw == 0) return 4; // Fallback when detection fails

#if defined(__ANDROID__)
    // Android big.LITTLE: use performance cores only (typically 4 of 8).
    // Using all cores causes thermal throttling under sustained inference load.
    return std::min(std::max(hw / 2, 1u), 4u);
#elif defined(__APPLE__)
    // iOS/macOS: Metal handles GPU compute; CPU threads for prompt eval.
    // Cap at 6 performance cores.
    return std::min(hw, 6u);
#else
    // Desktop Linux/Windows: cap at 8
    return std::min(hw, 8u);
#endif
}
