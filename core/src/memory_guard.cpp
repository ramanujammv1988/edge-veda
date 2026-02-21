/**
 * @file memory_guard.cpp
 * @brief Edge Veda SDK - Memory Watchdog Implementation
 *
 * Platform-specific memory monitoring and pressure management.
 * Supports macOS/iOS (mach_task_info), Linux/Android (/proc/self/statm),
 * and Windows (GetProcessMemoryInfo).
 */

#include <cstddef>
#include <cstdint>
#include <mutex>
#include <thread>
#include <atomic>
#include <chrono>

// Platform-specific includes
#if defined(__APPLE__)
    #include <mach/mach.h>
    #include <mach/task_info.h>
    #include <sys/sysctl.h>
#elif defined(__ANDROID__) || defined(__linux__)
    #include <unistd.h>
    #include <cstdio>
    #include <cstring>
#elif defined(_WIN32)
    #include <windows.h>
    #include <psapi.h>
#endif

/* ============================================================================
 * Memory Guard State
 * ========================================================================= */

namespace {

struct MemoryGuardState {
    // Memory limits and tracking
    std::atomic<size_t> memory_limit{0};
    std::atomic<size_t> current_usage{0};
    std::atomic<size_t> peak_usage{0};

    // Callback for memory pressure
    void (*pressure_callback)(void*, size_t, size_t) = nullptr;
    void* callback_user_data = nullptr;

    // Monitoring thread
    std::atomic<bool> monitoring_active{false};
    std::thread monitor_thread;

    // Thread safety
    std::mutex mutex;

    // Configuration
    std::chrono::milliseconds check_interval{1000}; // Check every 1 second
    float pressure_threshold{0.9f}; // Trigger callback at 90% of limit
    bool auto_cleanup{true};

    ~MemoryGuardState() noexcept {
        monitoring_active.store(false, std::memory_order_release);
        if (monitor_thread.joinable()) {
            try {
                monitor_thread.join();
            } catch (...) {
                // Never throw from static teardown.
            }
        }
    }
};

MemoryGuardState g_memory_guard;

} // anonymous namespace

/* ============================================================================
 * Platform-Specific Memory Usage Functions
 * ========================================================================= */

#if defined(__APPLE__)

/**
 * Get current memory usage on macOS/iOS using mach_task_info
 */
static size_t get_platform_memory_usage() {
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;

    kern_return_t kr = task_info(
        mach_task_self(),
        MACH_TASK_BASIC_INFO,
        reinterpret_cast<task_info_t>(&info),
        &count
    );

    if (kr != KERN_SUCCESS) {
        return 0;
    }

    // Return resident memory size (physical memory actually used)
    return static_cast<size_t>(info.resident_size);
}

/**
 * Get total available physical memory on macOS/iOS
 */
static size_t get_total_physical_memory() {
    int64_t memory_size = 0;
    size_t size = sizeof(memory_size);

    if (sysctlbyname("hw.memsize", &memory_size, &size, nullptr, 0) == 0) {
        return static_cast<size_t>(memory_size);
    }

    return 0;
}

#elif defined(__ANDROID__) || defined(__linux__)

/**
 * Get current memory usage on Linux/Android using /proc/self/statm
 */
static size_t get_platform_memory_usage() {
    FILE* file = fopen("/proc/self/statm", "r");
    if (!file) {
        return 0;
    }

    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        page_size = 4096; // Default to 4KB
    }

    unsigned long size, resident, shared, text, lib, data, dt;
    int result = fscanf(file, "%lu %lu %lu %lu %lu %lu %lu",
                       &size, &resident, &shared, &text, &lib, &data, &dt);
    fclose(file);

    if (result != 7) {
        return 0;
    }

    // Return resident set size (RSS) in bytes
    return static_cast<size_t>(resident * page_size);
}

/**
 * Get total available physical memory on Linux/Android
 */
static size_t get_total_physical_memory() {
    long pages = sysconf(_SC_PHYS_PAGES);
    long page_size = sysconf(_SC_PAGESIZE);

    if (pages > 0 && page_size > 0) {
        return static_cast<size_t>(pages * page_size);
    }

    return 0;
}

#elif defined(_WIN32)

/**
 * Get current memory usage on Windows using GetProcessMemoryInfo
 */
static size_t get_platform_memory_usage() {
    PROCESS_MEMORY_COUNTERS_EX pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(),
                            reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&pmc),
                            sizeof(pmc))) {
        // Return working set size (physical memory used)
        return static_cast<size_t>(pmc.WorkingSetSize);
    }

    return 0;
}

/**
 * Get total available physical memory on Windows
 */
static size_t get_total_physical_memory() {
    MEMORYSTATUSEX status;
    status.dwLength = sizeof(status);

    if (GlobalMemoryStatusEx(&status)) {
        return static_cast<size_t>(status.ullTotalPhys);
    }

    return 0;
}

#else

/**
 * Fallback for unsupported platforms
 */
static size_t get_platform_memory_usage() {
    return 0;
}

static size_t get_total_physical_memory() {
    return 0;
}

#endif

/* ============================================================================
 * Memory Monitoring Thread
 * ========================================================================= */

static void memory_monitor_loop() {
    while (g_memory_guard.monitoring_active.load(std::memory_order_acquire)) {
        // Get current memory usage
        size_t current = get_platform_memory_usage();
        g_memory_guard.current_usage.store(current, std::memory_order_release);

        // Update peak usage
        size_t peak = g_memory_guard.peak_usage.load(std::memory_order_acquire);
        while (current > peak) {
            if (g_memory_guard.peak_usage.compare_exchange_weak(
                    peak, current,
                    std::memory_order_release,
                    std::memory_order_acquire)) {
                break;
            }
        }

        // Check memory pressure
        size_t limit = g_memory_guard.memory_limit.load(std::memory_order_acquire);
        if (limit > 0 && current > 0) {
            float usage_ratio = static_cast<float>(current) / static_cast<float>(limit);

            // Trigger callback if threshold exceeded
            if (usage_ratio >= g_memory_guard.pressure_threshold) {
                std::lock_guard<std::mutex> lock(g_memory_guard.mutex);

                if (g_memory_guard.pressure_callback) {
                    g_memory_guard.pressure_callback(
                        g_memory_guard.callback_user_data,
                        current,
                        limit
                    );
                }

                // Auto-cleanup if enabled
                if (g_memory_guard.auto_cleanup && usage_ratio >= 0.95f) {
                    // TODO: Trigger cleanup in main library
                    // This would need to be coordinated with engine.cpp
                }
            }
        }

        // Sleep before next check
        std::this_thread::sleep_for(g_memory_guard.check_interval);
    }
}

static void start_monitoring() {
    if (g_memory_guard.monitoring_active.load(std::memory_order_acquire)) {
        return; // Already running
    }

    g_memory_guard.monitoring_active.store(true, std::memory_order_release);
    g_memory_guard.monitor_thread = std::thread(memory_monitor_loop);
}

static void stop_monitoring() {
    if (!g_memory_guard.monitoring_active.load(std::memory_order_acquire)) {
        return; // Not running
    }

    g_memory_guard.monitoring_active.store(false, std::memory_order_release);

    if (g_memory_guard.monitor_thread.joinable()) {
        g_memory_guard.monitor_thread.join();
    }
}

/* ============================================================================
 * Public C Interface
 * ========================================================================= */

extern "C" {

/**
 * @brief Get current memory usage in bytes
 * @return Current memory usage
 */
size_t memory_guard_get_current_usage() {
    size_t cached = g_memory_guard.current_usage.load(std::memory_order_acquire);

    // If monitoring is not active, query directly
    if (!g_memory_guard.monitoring_active.load(std::memory_order_acquire)) {
        return get_platform_memory_usage();
    }

    return cached;
}

/**
 * @brief Get peak memory usage in bytes
 * @return Peak memory usage since start
 */
size_t memory_guard_get_peak_usage() {
    return g_memory_guard.peak_usage.load(std::memory_order_acquire);
}

/**
 * @brief Get total available physical memory
 * @return Total physical memory in bytes
 */
size_t memory_guard_get_total_memory() {
    return get_total_physical_memory();
}

/**
 * @brief Set memory limit in bytes
 * @param limit_bytes Memory limit (0 = no limit)
 */
void memory_guard_set_limit(size_t limit_bytes) {
    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);

    g_memory_guard.memory_limit.store(limit_bytes, std::memory_order_release);

    // Start monitoring if limit is set and not already monitoring
    if (limit_bytes > 0) {
        start_monitoring();
    } else {
        stop_monitoring();
    }
}

/**
 * @brief Get current memory limit
 * @return Memory limit in bytes (0 = no limit)
 */
size_t memory_guard_get_limit() {
    return g_memory_guard.memory_limit.load(std::memory_order_acquire);
}

/**
 * @brief Set callback for memory pressure events
 * @param callback Callback function (nullptr to clear)
 * @param user_data User data to pass to callback
 */
void memory_guard_set_callback(
    void (*callback)(void*, size_t, size_t),
    void* user_data
) {
    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);

    g_memory_guard.pressure_callback = callback;
    g_memory_guard.callback_user_data = user_data;
}

/**
 * @brief Set memory pressure threshold (0.0 - 1.0)
 * @param threshold Threshold as fraction of limit (default: 0.9)
 */
void memory_guard_set_threshold(float threshold) {
    if (threshold < 0.0f) threshold = 0.0f;
    if (threshold > 1.0f) threshold = 1.0f;

    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);
    g_memory_guard.pressure_threshold = threshold;
}

/**
 * @brief Set monitoring check interval
 * @param interval_ms Interval in milliseconds (default: 1000)
 */
void memory_guard_set_check_interval(int interval_ms) {
    if (interval_ms < 100) interval_ms = 100; // Minimum 100ms
    if (interval_ms > 60000) interval_ms = 60000; // Maximum 60 seconds

    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);
    g_memory_guard.check_interval = std::chrono::milliseconds(interval_ms);
}

/**
 * @brief Enable or disable auto-cleanup
 * @param enable true to enable auto-cleanup
 */
void memory_guard_set_auto_cleanup(bool enable) {
    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);
    g_memory_guard.auto_cleanup = enable;
}

/**
 * @brief Manually trigger cleanup (force garbage collection)
 */
void memory_guard_cleanup() {
    // This is a placeholder for manual cleanup trigger
    // The actual cleanup would be coordinated with engine.cpp

    // Force a fresh memory reading
    size_t current = get_platform_memory_usage();
    g_memory_guard.current_usage.store(current, std::memory_order_release);
}

/**
 * @brief Reset memory statistics
 */
void memory_guard_reset_stats() {
    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);

    g_memory_guard.peak_usage.store(0, std::memory_order_release);
    g_memory_guard.current_usage.store(0, std::memory_order_release);
}

/**
 * @brief Start memory monitoring (usually called automatically)
 */
void memory_guard_start() {
    start_monitoring();
}

/**
 * @brief Stop memory monitoring and cleanup
 */
void memory_guard_stop() {
    stop_monitoring();

    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);
    g_memory_guard.pressure_callback = nullptr;
    g_memory_guard.callback_user_data = nullptr;
}

/**
 * @brief Initialize memory guard system
 */
void memory_guard_init() {
    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);

    // Initialize with current usage
    size_t current = get_platform_memory_usage();
    g_memory_guard.current_usage.store(current, std::memory_order_release);
    g_memory_guard.peak_usage.store(current, std::memory_order_release);
}

/**
 * @brief Shutdown memory guard system
 */
void memory_guard_shutdown() {
    stop_monitoring();
    memory_guard_reset_stats();

    std::lock_guard<std::mutex> lock(g_memory_guard.mutex);
    g_memory_guard.memory_limit.store(0, std::memory_order_release);
    g_memory_guard.pressure_callback = nullptr;
    g_memory_guard.callback_user_data = nullptr;
}

/**
 * @brief Get memory usage statistics as percentage
 * @return Usage as percentage of limit (0.0 - 100.0), or -1.0 if no limit set
 */
float memory_guard_get_usage_percentage() {
    size_t current = g_memory_guard.current_usage.load(std::memory_order_acquire);
    size_t limit = g_memory_guard.memory_limit.load(std::memory_order_acquire);

    if (limit == 0) {
        return -1.0f;
    }

    return (static_cast<float>(current) / static_cast<float>(limit)) * 100.0f;
}

/**
 * @brief Check if memory is under pressure
 * @return true if usage exceeds threshold
 */
bool memory_guard_is_under_pressure() {
    size_t current = g_memory_guard.current_usage.load(std::memory_order_acquire);
    size_t limit = g_memory_guard.memory_limit.load(std::memory_order_acquire);

    if (limit == 0) {
        return false;
    }

    float usage_ratio = static_cast<float>(current) / static_cast<float>(limit);
    return usage_ratio >= g_memory_guard.pressure_threshold;
}

/**
 * @brief Get recommended memory limit for device
 *
 * Returns a conservative memory limit based on platform and device memory.
 * - iOS: 1.2GB (iOS jetsam is relatively predictable)
 * - Android: 800MB (LMK more aggressive, especially on 4GB devices)
 * - Desktop: 60% of total (more headroom available)
 *
 * @return Recommended limit in bytes
 */
size_t memory_guard_get_recommended_limit() {
    size_t total = get_total_physical_memory();

    if (total == 0) {
        return 0;
    }

#if defined(__ANDROID__)
    // Android LMK is more aggressive than iOS jetsam
    // On 4GB devices, background apps get killed around 1GB foreground app usage
    // Use 800MB as conservative default (per v1.1 research)
    constexpr size_t ANDROID_DEFAULT_LIMIT = 800 * 1024 * 1024; // 800MB

    // If device has lots of RAM (12GB+), allow more
    if (total >= 12ULL * 1024 * 1024 * 1024) {
        return 1200 * 1024 * 1024; // 1.2GB on flagship devices
    } else if (total >= 8ULL * 1024 * 1024 * 1024) {
        return 1000 * 1024 * 1024; // 1GB on 8GB devices
    } else {
        return ANDROID_DEFAULT_LIMIT; // 800MB on 4-6GB devices
    }
#elif defined(__APPLE__)
    // iOS: Use 1.2GB default (validated in v1.0)
    // This is more generous because iOS jetsam warnings give time to react
    constexpr size_t IOS_DEFAULT_LIMIT = 1200 * 1024 * 1024; // 1.2GB
    return IOS_DEFAULT_LIMIT;
#else
    // Desktop: Use 60% of total memory
    return static_cast<size_t>(total * 0.6);
#endif
}

} // extern "C"

/* ============================================================================
 * Platform-Specific Utilities
 * ========================================================================= */

#if defined(__ANDROID__)

extern "C" {

/**
 * @brief Android-specific: Get memory info from /proc/meminfo
 */
void memory_guard_get_android_meminfo(
    size_t* total,
    size_t* available,
    size_t* free
) {
    if (!total && !available && !free) {
        return;
    }

    FILE* file = fopen("/proc/meminfo", "r");
    if (!file) {
        return;
    }

    char line[256];
    while (fgets(line, sizeof(line), file)) {
        unsigned long value;

        if (total && sscanf(line, "MemTotal: %lu kB", &value) == 1) {
            *total = value * 1024;
        } else if (available && sscanf(line, "MemAvailable: %lu kB", &value) == 1) {
            *available = value * 1024;
        } else if (free && sscanf(line, "MemFree: %lu kB", &value) == 1) {
            *free = value * 1024;
        }
    }

    fclose(file);
}

/**
 * @brief Get Android available memory from /proc/meminfo
 *
 * MemAvailable is the kernel's estimate of memory available for new
 * allocations without triggering swap or OOM. More accurate than MemFree.
 *
 * @return Available memory in bytes, or 0 if unavailable
 */
size_t memory_guard_get_android_available() {
    size_t available = 0;
    memory_guard_get_android_meminfo(nullptr, &available, nullptr);
    return available;
}

} // extern "C"

#endif // __ANDROID__

#if defined(__APPLE__)

extern "C" {

/**
 * @brief iOS/macOS-specific: Get detailed VM statistics
 */
void memory_guard_get_apple_vm_stats(
    size_t* wired,
    size_t* active,
    size_t* inactive,
    size_t* free_count
) {
    vm_statistics64_data_t vm_stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;

    kern_return_t kr = host_statistics64(
        mach_host_self(),
        HOST_VM_INFO64,
        reinterpret_cast<host_info64_t>(&vm_stats),
        &count
    );

    if (kr != KERN_SUCCESS) {
        return;
    }

    vm_size_t page_size;
    kr = host_page_size(mach_host_self(), &page_size);
    if (kr != KERN_SUCCESS) {
        page_size = 4096; // Default
    }

    if (wired) {
        *wired = static_cast<size_t>(vm_stats.wire_count * page_size);
    }
    if (active) {
        *active = static_cast<size_t>(vm_stats.active_count * page_size);
    }
    if (inactive) {
        *inactive = static_cast<size_t>(vm_stats.inactive_count * page_size);
    }
    if (free_count) {
        *free_count = static_cast<size_t>(vm_stats.free_count * page_size);
    }
}

} // extern "C"

#endif // __APPLE__
