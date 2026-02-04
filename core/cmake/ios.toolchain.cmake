# iOS CMake Toolchain File for Ninja/Makefile Generator
# Usage:
#   cmake -G Ninja \
#         -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
#         -DPLATFORM=OS64 \
#         -DDEPLOYMENT_TARGET=13.0 \
#         ..
#
# PLATFORM options:
#   OS64           - Device (arm64)
#   SIMULATORARM64 - Simulator (arm64, for M1+ Macs)

cmake_minimum_required(VERSION 3.21)

# Platform selection
if(NOT DEFINED PLATFORM)
    set(PLATFORM "OS64")
endif()

# Deployment target
if(NOT DEFINED DEPLOYMENT_TARGET)
    set(DEPLOYMENT_TARGET "13.0")
endif()

# iOS system
set(CMAKE_SYSTEM_NAME iOS CACHE INTERNAL "")
set(CMAKE_SYSTEM_VERSION ${DEPLOYMENT_TARGET} CACHE INTERNAL "")

# Configure based on platform
if(PLATFORM STREQUAL "OS64" OR PLATFORM STREQUAL "OS")
    set(_sdk_name "iphoneos")
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "")
    set(IOS_PLATFORM_DEVICE TRUE CACHE BOOL "Building for device")
    set(IOS_PLATFORM_SIMULATOR FALSE CACHE BOOL "")
elseif(PLATFORM STREQUAL "SIMULATORARM64")
    set(_sdk_name "iphonesimulator")
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "")
    set(IOS_PLATFORM_DEVICE FALSE CACHE BOOL "")
    set(IOS_PLATFORM_SIMULATOR TRUE CACHE BOOL "Building for simulator")
elseif(PLATFORM STREQUAL "SIMULATOR64")
    set(_sdk_name "iphonesimulator")
    set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "")
    set(IOS_PLATFORM_DEVICE FALSE CACHE BOOL "")
    set(IOS_PLATFORM_SIMULATOR TRUE CACHE BOOL "Building for simulator")
else()
    message(FATAL_ERROR "Invalid PLATFORM: ${PLATFORM}. Use OS64, SIMULATORARM64, or SIMULATOR64")
endif()

# Get SDK path
execute_process(
    COMMAND xcrun --sdk ${_sdk_name} --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Get compilers from SDK
execute_process(
    COMMAND xcrun --sdk ${_sdk_name} --find clang
    OUTPUT_VARIABLE CMAKE_C_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND xcrun --sdk ${_sdk_name} --find clang++
    OUTPUT_VARIABLE CMAKE_CXX_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND xcrun --sdk ${_sdk_name} --find ar
    OUTPUT_VARIABLE CMAKE_AR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND xcrun --sdk ${_sdk_name} --find ranlib
    OUTPUT_VARIABLE CMAKE_RANLIB
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Set deployment target
set(CMAKE_OSX_DEPLOYMENT_TARGET ${DEPLOYMENT_TARGET} CACHE STRING "Minimum iOS version")

# Build flags - no bitcode (ensure native code generation for XCFramework compatibility)
set(_ios_arch_flags "-arch ${CMAKE_OSX_ARCHITECTURES} -isysroot ${CMAKE_OSX_SYSROOT}")
set(_ios_version_flags "-m${_sdk_name}-version-min=${DEPLOYMENT_TARGET}")

set(CMAKE_C_FLAGS_INIT "${_ios_arch_flags} ${_ios_version_flags}")
set(CMAKE_CXX_FLAGS_INIT "${_ios_arch_flags} ${_ios_version_flags}")
set(CMAKE_ASM_FLAGS_INIT "${_ios_arch_flags} ${_ios_version_flags}")

# Optimization flags for Release builds
set(CMAKE_C_FLAGS_RELEASE_INIT "-O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "-O3 -DNDEBUG")

# Skip try_compile for cross-compilation
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY CACHE INTERNAL "")

# Threads are always available on iOS
set(THREADS_FOUND TRUE CACHE BOOL "")
set(CMAKE_THREAD_LIBS_INIT "" CACHE STRING "")
set(CMAKE_HAVE_THREADS_LIBRARY TRUE CACHE BOOL "")
set(CMAKE_USE_PTHREADS_INIT TRUE CACHE BOOL "")
set(Threads_FOUND TRUE CACHE BOOL "")

# Metal support flags
if(IOS_PLATFORM_DEVICE)
    add_compile_definitions(USE_METAL=1)
    add_compile_definitions(GGML_USE_METAL=1)
endif()

# Cross-compilation find settings
set(CMAKE_FIND_ROOT_PATH ${CMAKE_OSX_SYSROOT} CACHE STRING "")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER CACHE STRING "")
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY CACHE STRING "")
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY CACHE STRING "")
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY CACHE STRING "")

# Print configuration
message(STATUS "iOS Toolchain Configuration:")
message(STATUS "  Platform: ${PLATFORM}")
message(STATUS "  Architectures: ${CMAKE_OSX_ARCHITECTURES}")
message(STATUS "  Deployment Target: ${DEPLOYMENT_TARGET}")
message(STATUS "  SDK: ${CMAKE_OSX_SYSROOT}")
message(STATUS "  C Compiler: ${CMAKE_C_COMPILER}")
message(STATUS "  CXX Compiler: ${CMAKE_CXX_COMPILER}")
message(STATUS "  Device Build: ${IOS_PLATFORM_DEVICE}")
message(STATUS "  Simulator Build: ${IOS_PLATFORM_SIMULATOR}")
