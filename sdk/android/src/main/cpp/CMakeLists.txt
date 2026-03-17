cmake_minimum_required(VERSION 3.22.1)
project(edge_veda_android)

set(CMAKE_CXX_STANDARD 17)

# Path to the Edge Veda core library
set(CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../core")

# Add core as subdirectory (builds llama.cpp + edge_veda)
add_subdirectory(${CORE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/core)

# JNI bridge
add_library(edge_veda_jni SHARED edge_veda_jni.cpp)

target_include_directories(edge_veda_jni PRIVATE
    ${CORE_DIR}/include
)

target_link_libraries(edge_veda_jni
    edge_veda
    android
    log
)
