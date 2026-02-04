# Android NDK CMake Toolchain File
# This toolchain file configures CMake for Android NDK cross-compilation
# Wraps the official Android NDK toolchain with project-specific settings
#
# Usage:
#   cmake -DCMAKE_TOOLCHAIN_FILE=cmake/android.toolchain.cmake \
#         -DANDROID_ABI=arm64-v8a \
#         -DANDROID_PLATFORM=android-24 \
#         -DANDROID_NDK=/path/to/ndk \
#         ..
#
# Required variables:
#   ANDROID_NDK - Path to Android NDK (or set ANDROID_NDK_HOME env var)
#
# Optional variables:
#   ANDROID_ABI - Target ABI (default: arm64-v8a)
#                 Options: arm64-v8a, armeabi-v7a, x86_64, x86
#   ANDROID_PLATFORM - Minimum API level (default: android-24)
#   ANDROID_STL - STL variant (default: c++_shared)
#                 Options: c++_shared, c++_static, none

cmake_minimum_required(VERSION 3.21)

# Detect Android NDK path
if(NOT DEFINED ANDROID_NDK)
    if(DEFINED ENV{ANDROID_NDK})
        set(ANDROID_NDK $ENV{ANDROID_NDK})
    elseif(DEFINED ENV{ANDROID_NDK_HOME})
        set(ANDROID_NDK $ENV{ANDROID_NDK_HOME})
    elseif(DEFINED ENV{NDK_ROOT})
        set(ANDROID_NDK $ENV{NDK_ROOT})
    else()
        message(FATAL_ERROR "ANDROID_NDK not found. Please set ANDROID_NDK, ANDROID_NDK_HOME, or NDK_ROOT environment variable")
    endif()
endif()

# Validate NDK path
if(NOT EXISTS ${ANDROID_NDK})
    message(FATAL_ERROR "ANDROID_NDK path does not exist: ${ANDROID_NDK}")
endif()

# Find the official Android NDK toolchain file
set(ANDROID_NDK_TOOLCHAIN_FILE "${ANDROID_NDK}/build/cmake/android.toolchain.cmake")
if(NOT EXISTS ${ANDROID_NDK_TOOLCHAIN_FILE})
    message(FATAL_ERROR "Android NDK toolchain file not found: ${ANDROID_NDK_TOOLCHAIN_FILE}")
endif()

# Default configuration
if(NOT DEFINED ANDROID_ABI)
    set(ANDROID_ABI "arm64-v8a")
endif()

if(NOT DEFINED ANDROID_PLATFORM)
    set(ANDROID_PLATFORM "android-24")
endif()

if(NOT DEFINED ANDROID_STL)
    set(ANDROID_STL "c++_shared")
endif()

# Enable NEON for ARM targets
if(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(ANDROID_ARM_NEON ON)
endif()

# Include the official NDK toolchain
include(${ANDROID_NDK_TOOLCHAIN_FILE})

# Additional compiler flags for optimization
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC")

# Release optimization flags
set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG -ffast-math -fno-finite-math-only")
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -ffast-math -fno-finite-math-only")

# Enable LTO for release builds (optional)
if(ENABLE_LTO)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
    set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -flto=thin")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -flto=thin")
endif()

# Architecture-specific optimizations
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=armv8-a")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a")
    add_compile_definitions(USE_NEON=1)
    add_compile_definitions(GGML_USE_NEON=1)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=armv7-a -mfpu=neon")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv7-a -mfpu=neon")
    add_compile_definitions(USE_NEON=1)
    add_compile_definitions(GGML_USE_NEON=1)
elseif(ANDROID_ABI STREQUAL "x86_64")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -msse4.2")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -msse4.2")
endif()

# Vulkan support detection
find_path(VULKAN_INCLUDE_DIR vulkan/vulkan.h
    PATHS ${ANDROID_NDK}/sources/third_party/vulkan/src/include
    NO_DEFAULT_PATH
)

if(VULKAN_INCLUDE_DIR)
    message(STATUS "Vulkan headers found: ${VULKAN_INCLUDE_DIR}")
    set(VULKAN_AVAILABLE ON)
    add_compile_definitions(USE_VULKAN=1)
else()
    message(WARNING "Vulkan headers not found in NDK. GPU acceleration will be limited.")
    set(VULKAN_AVAILABLE OFF)
endif()

# NNAPI support (API 27+)
if(ANDROID_PLATFORM_LEVEL GREATER_EQUAL 27)
    add_compile_definitions(USE_NNAPI=1)
    message(STATUS "NNAPI support enabled (API ${ANDROID_PLATFORM_LEVEL})")
endif()

# Linker flags
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--gc-sections")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--gc-sections")

# Strip symbols in release builds
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -s")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -s")
endif()

# Helper function to link Android libraries
function(link_android_libs target)
    target_link_libraries(${target} PRIVATE
        android
        log
        m
    )
endfunction()

# Helper function to link Vulkan
function(link_vulkan target)
    if(VULKAN_AVAILABLE)
        target_include_directories(${target} PRIVATE ${VULKAN_INCLUDE_DIR})
        target_link_libraries(${target} PRIVATE vulkan)
    endif()
endfunction()

# Helper function to link NNAPI
function(link_nnapi target)
    if(ANDROID_PLATFORM_LEVEL GREATER_EQUAL 27)
        target_link_libraries(${target} PRIVATE dl)
    endif()
endfunction()

# Helper function for multi-ABI build
function(configure_multi_abi_build)
    set(ANDROID_ABIS "arm64-v8a;armeabi-v7a;x86_64;x86" CACHE STRING "Android ABIs to build")
    message(STATUS "Configured for multi-ABI build: ${ANDROID_ABIS}")
endfunction()

# Print configuration summary
message(STATUS "Android NDK Toolchain Configuration:")
message(STATUS "  NDK Path: ${ANDROID_NDK}")
message(STATUS "  NDK Version: ${ANDROID_NDK_MAJOR}.${ANDROID_NDK_MINOR}")
message(STATUS "  Target ABI: ${ANDROID_ABI}")
message(STATUS "  Platform: ${ANDROID_PLATFORM} (API ${ANDROID_PLATFORM_LEVEL})")
message(STATUS "  STL: ${ANDROID_STL}")
message(STATUS "  Compiler: ${CMAKE_CXX_COMPILER}")
message(STATUS "  Vulkan Support: ${VULKAN_AVAILABLE}")
if(ANDROID_PLATFORM_LEVEL GREATER_EQUAL 27)
    message(STATUS "  NNAPI Support: ON")
else()
    message(STATUS "  NNAPI Support: OFF (requires API 27+)")
endif()

# Additional Android-specific settings
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)

# Export compile commands for IDE support
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
