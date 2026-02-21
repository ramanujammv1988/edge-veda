cmake_minimum_required(VERSION 3.15)
project(edge_veda VERSION 1.0.0 LANGUAGES CXX C)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Export compile commands for IDE support
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Platform detection
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(IOS TRUE)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Android")
    set(ANDROID TRUE)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(MACOS TRUE)
endif()

# Backend options - compute default values first
if(IOS OR MACOS)
    set(METAL_DEFAULT ON)
else()
    set(METAL_DEFAULT OFF)
endif()

option(EDGE_VEDA_ENABLE_METAL "Enable Metal backend for iOS/macOS" ${METAL_DEFAULT})
option(EDGE_VEDA_ENABLE_VULKAN "Enable Vulkan backend for Android" OFF)  # Phase 5: CPU-only, Vulkan deferred to Phase 7
option(EDGE_VEDA_ENABLE_CPU "Enable CPU backend (always available)" ON)
option(EDGE_VEDA_BUILD_SHARED "Build shared library" ON)
option(EDGE_VEDA_BUILD_STATIC "Build static library" OFF)
option(EDGE_VEDA_BUILD_TESTS "Build tests" OFF)

# Enable LTO for release builds (reduces binary size ~10-20%)
# CMAKE_INTERPROCEDURAL_OPTIMIZATION uses -flto=thin on Android (Clang)
# Note: keep LTO disabled for Apple XCFramework static archives.
if(CMAKE_BUILD_TYPE STREQUAL "Release" AND ANDROID)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()

# Platform-specific flags
if(IOS)
    # iOS cross-compilation settings
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum iOS version")
    set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
    set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build for arm64 only")

    # Metal framework requirement
    if(EDGE_VEDA_ENABLE_METAL)
        find_library(METAL_FRAMEWORK Metal REQUIRED)
        find_library(METALKIT_FRAMEWORK MetalKit REQUIRED)
        find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
        find_library(ACCELERATE_FRAMEWORK Accelerate REQUIRED)
    endif()
elseif(ANDROID)
    # Android cross-compilation settings
    # These should be set via Android NDK toolchain file
    set(CMAKE_ANDROID_API_MIN 24)
    set(CMAKE_ANDROID_STL_TYPE c++_shared)

    # Vulkan requirement for Android
    if(EDGE_VEDA_ENABLE_VULKAN)
        find_package(Vulkan REQUIRED)
    endif()
elseif(MACOS)
    # macOS settings
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")

    if(EDGE_VEDA_ENABLE_METAL)
        find_library(METAL_FRAMEWORK Metal REQUIRED)
        find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    endif()
endif()

# Source files
set(EDGE_VEDA_SOURCES
    src/engine.cpp
    src/memory_guard.cpp
    src/vision_engine.cpp
    src/whisper_engine.cpp
)

# Header files
set(EDGE_VEDA_HEADERS
    include/edge_veda.h
)

# Backend compile definitions (actual backends handled by llama.cpp)
if(EDGE_VEDA_ENABLE_METAL)
    add_compile_definitions(EDGE_VEDA_METAL_ENABLED)
endif()

if(EDGE_VEDA_ENABLE_VULKAN)
    add_compile_definitions(EDGE_VEDA_VULKAN_ENABLED)
endif()

if(EDGE_VEDA_ENABLE_CPU)
    add_compile_definitions(EDGE_VEDA_CPU_ENABLED)
endif()

# Android-specific llama.cpp configuration (BEFORE add_subdirectory)
if(ANDROID)
    # CRITICAL: CPU-only build for Phase 5 (Vulkan deferred to Phase 7)
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)

    # CRITICAL: Disable OpenMP - causes dlopen failures on many Android devices
    # that don't ship libgomp. CPU backend works fine without it.
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

    # Disable LLAMAFILE - x86 optimizations not needed on ARM64
    set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

    # Enable NEON (ARM SIMD) - automatic on arm64 but be explicit
    set(GGML_NEON ON CACHE BOOL "" FORCE)
endif()

# Include llama.cpp as subdirectory
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp/CMakeLists.txt")
    # Disable tests/examples/server (reduces build time and size)
    set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

    # Enable common + tools to build libmtmd (multimodal/vision support)
    # mtmd library lives in tools/mtmd and requires LLAMA_BUILD_COMMON + LLAMA_BUILD_TOOLS
    set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_TOOLS ON CACHE BOOL "" FORCE)

    # Disable optional common dependencies not needed for mtmd
    set(LLAMA_HTTPLIB OFF CACHE BOOL "" FORCE)
    set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
    set(LLAMA_LLGUIDANCE OFF CACHE BOOL "" FORCE)

    # Metal configuration for iOS/macOS (using GGML_METAL, not deprecated LLAMA_METAL)
    if(IOS OR MACOS)
        set(GGML_METAL ON CACHE BOOL "" FORCE)
        set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
    endif()

    # Accelerate framework for Apple platforms
    if(APPLE)
        set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    endif()

    # Enable Vulkan for llama.cpp on Android
    if(EDGE_VEDA_ENABLE_VULKAN)
        set(GGML_VULKAN ON CACHE BOOL "" FORCE)
    endif()

    # CRITICAL: Disable desktop SIMD to prevent binary bloat on iOS
    # These x86 instructions are not needed on arm64 and would bloat the binary
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
    set(GGML_AVX OFF CACHE BOOL "" FORCE)
    set(GGML_AVX2 OFF CACHE BOOL "" FORCE)
    set(GGML_AVX512 OFF CACHE BOOL "" FORCE)
    set(GGML_AVX512_VBMI OFF CACHE BOOL "" FORCE)
    set(GGML_AVX512_VNNI OFF CACHE BOOL "" FORCE)
    set(GGML_FMA OFF CACHE BOOL "" FORCE)
    set(GGML_F16C OFF CACHE BOOL "" FORCE)

    # Keep ARM NEON (automatic on iOS arm64)

    add_subdirectory(third_party/llama.cpp)
    set(LLAMA_CPP_AVAILABLE TRUE)
else()
    message(WARNING "llama.cpp not found in third_party/llama.cpp - library will build without LLM support")
    set(LLAMA_CPP_AVAILABLE FALSE)
endif()

# Include whisper.cpp as subdirectory (MUST come AFTER llama.cpp so ggml targets exist)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/whisper.cpp/CMakeLists.txt")
    # whisper.cpp checks `if (NOT TARGET ggml)` and skips building its own ggml
    # when the ggml target already exists from llama.cpp above.
    # Setting WHISPER_USE_SYSTEM_GGML is a fallback in case the target check changes.
    set(WHISPER_USE_SYSTEM_GGML ON CACHE BOOL "" FORCE)
    set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
    set(WHISPER_SDL2 OFF CACHE BOOL "" FORCE)
    set(WHISPER_FFMPEG OFF CACHE BOOL "" FORCE)
    set(WHISPER_COREML OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    add_subdirectory(third_party/whisper.cpp)
    set(WHISPER_CPP_AVAILABLE TRUE)
else()
    message(WARNING "whisper.cpp not found in third_party/whisper.cpp - STT support disabled")
    set(WHISPER_CPP_AVAILABLE FALSE)
endif()

# Create library target
if(EDGE_VEDA_BUILD_SHARED)
    add_library(edge_veda SHARED ${EDGE_VEDA_SOURCES} ${EDGE_VEDA_HEADERS})
    target_compile_definitions(edge_veda PRIVATE EDGE_VEDA_BUILD_SHARED)

    # Set version for shared library
    set_target_properties(edge_veda PROPERTIES
        VERSION ${PROJECT_VERSION}
        SOVERSION ${PROJECT_VERSION_MAJOR}
    )
endif()

if(EDGE_VEDA_BUILD_STATIC)
    add_library(edge_veda_static STATIC ${EDGE_VEDA_SOURCES} ${EDGE_VEDA_HEADERS})
    target_compile_definitions(edge_veda_static PUBLIC EDGE_VEDA_STATIC)
    set_target_properties(edge_veda_static PROPERTIES OUTPUT_NAME edge_veda)
endif()

# Function to configure target (shared or static)
function(configure_edge_veda_target target_name)
    # Include directories
    target_include_directories(${target_name}
        PUBLIC
            $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:include>
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    # Link llama.cpp if available (llama, ggml, and mtmd libraries)
    if(LLAMA_CPP_AVAILABLE)
        target_link_libraries(${target_name} PRIVATE llama ggml mtmd)
        target_compile_definitions(${target_name} PRIVATE EDGE_VEDA_LLAMA_ENABLED)
        target_include_directories(${target_name} PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp/include
            ${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp/ggml/include
            ${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp/tools/mtmd
        )
    endif()

    # Link whisper.cpp if available (shares ggml from llama.cpp)
    if(WHISPER_CPP_AVAILABLE)
        target_link_libraries(${target_name} PRIVATE whisper)
        target_compile_definitions(${target_name} PRIVATE EDGE_VEDA_WHISPER_ENABLED)
        target_include_directories(${target_name} PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/third_party/whisper.cpp/include
        )
    endif()

    # Platform-specific linking
    if(IOS OR MACOS)
        if(EDGE_VEDA_ENABLE_METAL)
            target_link_libraries(${target_name} PRIVATE
                ${METAL_FRAMEWORK}
                ${FOUNDATION_FRAMEWORK}
            )
        endif()

        # Link system libraries for memory monitoring
        target_link_libraries(${target_name} PRIVATE "-framework CoreFoundation")
    elseif(ANDROID)
        if(EDGE_VEDA_ENABLE_VULKAN)
            target_link_libraries(${target_name} PRIVATE Vulkan::Vulkan)
        endif()

        # Link Android logging and system libraries
        target_link_libraries(${target_name} PRIVATE log android)

        # 16KB page alignment for Android 15+ (Google Play requirement Nov 2025)
        target_link_options(${target_name} PRIVATE
            -Wl,-z,max-page-size=16384
            -Wl,-z,common-page-size=16384
        )
    elseif(UNIX)
        # Linux needs pthread for threading
        find_package(Threads REQUIRED)
        target_link_libraries(${target_name} PRIVATE Threads::Threads)
    endif()

    # Compiler warnings
    if(MSVC)
        target_compile_options(${target_name} PRIVATE /W4 /WX)
    else()
        target_compile_options(${target_name} PRIVATE
            -Wall -Wextra -Wpedantic -Werror
            -Wno-unused-parameter  # Common in stub implementations
        )
    endif()

    # Position independent code for shared libraries
    set_target_properties(${target_name} PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
    )

    # iOS specific settings
    if(IOS)
        set_target_properties(${target_name} PROPERTIES
            FRAMEWORK TRUE
            FRAMEWORK_VERSION A
            MACOSX_FRAMEWORK_IDENTIFIER com.edgeveda.core
            XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "iPhone Developer"
        )
    endif()
endfunction()

# Configure targets
if(EDGE_VEDA_BUILD_SHARED)
    configure_edge_veda_target(edge_veda)
endif()

if(EDGE_VEDA_BUILD_STATIC)
    configure_edge_veda_target(edge_veda_static)
endif()

# Installation rules (simplified - no export since llama.cpp handles its own)
if(EDGE_VEDA_BUILD_SHARED)
    install(TARGETS edge_veda
        LIBRARY DESTINATION lib
        ARCHIVE DESTINATION lib
        RUNTIME DESTINATION bin
        FRAMEWORK DESTINATION lib
    )
endif()

if(EDGE_VEDA_BUILD_STATIC)
    install(TARGETS edge_veda_static
        LIBRARY DESTINATION lib
        ARCHIVE DESTINATION lib
        FRAMEWORK DESTINATION lib
    )
endif()

# Install headers
install(FILES ${EDGE_VEDA_HEADERS} DESTINATION include)

# Tests (optional)
if(EDGE_VEDA_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# Print configuration summary
message(STATUS "")
message(STATUS "Edge Veda SDK Configuration:")
message(STATUS "  Version: ${PROJECT_VERSION}")
message(STATUS "  Platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "  Build shared: ${EDGE_VEDA_BUILD_SHARED}")
message(STATUS "  Build static: ${EDGE_VEDA_BUILD_STATIC}")
message(STATUS "  Metal backend: ${EDGE_VEDA_ENABLE_METAL}")
message(STATUS "  Vulkan backend: ${EDGE_VEDA_ENABLE_VULKAN}")
message(STATUS "  CPU backend: ${EDGE_VEDA_ENABLE_CPU}")
message(STATUS "  llama.cpp available: ${LLAMA_CPP_AVAILABLE}")
message(STATUS "  whisper.cpp available: ${WHISPER_CPP_AVAILABLE}")
message(STATUS "")
