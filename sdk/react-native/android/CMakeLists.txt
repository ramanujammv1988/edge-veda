cmake_minimum_required(VERSION 3.22.1)
project(edge_veda_rn)

set(CMAKE_CXX_STANDARD 17)
set(CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../core")

add_subdirectory(${CORE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/core)

add_library(edge_veda_rn SHARED
    src/main/cpp/edge_veda_rn_jni.cpp
)

target_include_directories(edge_veda_rn PRIVATE
    ${CORE_DIR}/include
)

target_link_libraries(edge_veda_rn
    edge_veda
    android
    log
)
