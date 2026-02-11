cmake_minimum_required(VERSION 3.22.1)

project(edgeveda_jni)

# C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Compiler flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Werror")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -O0 -g -DDEBUG")

# Find log library
find_library(log-lib log)

# Android logging support
find_library(android-lib android)

# Find NDK libraries
find_library(VULKAN_LIB vulkan)

# JNI source files
set(JNI_SOURCES
    edge_veda_jni.cpp
)

# Create shared library
add_library(edgeveda_jni SHARED ${JNI_SOURCES})

# Include directories
target_include_directories(edgeveda_jni PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../core/include
    ${ANDROID_NDK}/sources/android/native_app_glue
)

# Add library search path for Edge Veda core
link_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../core/build
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../core/build/${ANDROID_ABI}
)

# Link libraries
target_link_libraries(edgeveda_jni
    ${log-lib}
    ${android-lib}
    ${VULKAN_LIB}
    edge_veda
    c++_shared
)

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
