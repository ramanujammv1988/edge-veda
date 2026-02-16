cmake_minimum_required(VERSION 3.22.1)

project(edgeveda_jni)

# C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Compiler flags (no -Werror — llama.cpp has warnings we can't control)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -O0 -g")

# Find log library
find_library(log-lib log)

# Android logging support
find_library(android-lib android)

# ============================================================================
# Include the Edge Veda core library (which includes llama.cpp as subdirectory)
# This builds: edge_veda_static (static lib with llama.cpp + ggml + mtmd)
# ============================================================================
set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../core)

# Configure core to build static library only (we'll link it into the JNI shared lib)
set(EDGE_VEDA_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(EDGE_VEDA_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(EDGE_VEDA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(EDGE_VEDA_ENABLE_METAL OFF CACHE BOOL "" FORCE)
set(EDGE_VEDA_ENABLE_VULKAN OFF CACHE BOOL "" FORCE)
set(EDGE_VEDA_ENABLE_CPU ON CACHE BOOL "" FORCE)

# Disable llama.cpp tools/common/examples — we only need the core llama + ggml libraries
# (mtmd has Android NDK build issues with corrupted submodule checkout)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)

add_subdirectory(${CORE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/core)

# ============================================================================
# JNI shared library
# ============================================================================
set(JNI_SOURCES
    edge_veda_jni.cpp
)

# Create shared library
add_library(edgeveda_jni SHARED ${JNI_SOURCES})

# Include directories
target_include_directories(edgeveda_jni PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CORE_DIR}/include
    ${ANDROID_NDK}/sources/android/native_app_glue
)

# Link against the static core library (which transitively includes llama.cpp)
target_link_libraries(edgeveda_jni
    edge_veda_static
    ${log-lib}
    ${android-lib}
)

# 16 KB page size alignment (required for Android 15+ / Google Play since Nov 2025)
target_link_options(edgeveda_jni PRIVATE -Wl,-z,max-page-size=16384)

# Export JNI symbols
set_target_properties(edgeveda_jni PROPERTIES
    LINK_FLAGS "-Wl,--exclude-libs,ALL"
)

# Strip symbols in release builds
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    add_custom_command(TARGET edgeveda_jni POST_BUILD
        COMMAND ${CMAKE_STRIP} --strip-unneeded $<TARGET_FILE:edgeveda_jni>
    )
endif()

# Optional: Add support for Address Sanitizer in debug builds
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    option(USE_ASAN "Enable Address Sanitizer" OFF)
    if(USE_ASAN)
        target_compile_options(edgeveda_jni PRIVATE -fsanitize=address -fno-omit-frame-pointer)
        target_link_options(edgeveda_jni PRIVATE -fsanitize=address)
    endif()
endif()