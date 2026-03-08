# Edge Veda Core Tests
cmake_minimum_required(VERSION 3.15)

# Test inference executable (requires model file -- not CI-safe)
add_executable(test_inference test_inference.cpp)

target_link_libraries(test_inference PRIVATE edge_veda_static)

target_include_directories(test_inference PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

# Copy test to output directory
set_target_properties(test_inference PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)

# CI-safe NULL-path guard tests (no model file needed)
add_executable(test_api_guards test_api_guards.cpp)

target_link_libraries(test_api_guards PRIVATE edge_veda_static)
target_compile_definitions(test_api_guards PRIVATE EDGE_VEDA_TEST_HOOKS)

target_include_directories(test_api_guards PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

set_target_properties(test_api_guards PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)

# ctest discovery
add_test(NAME api_guards COMMAND test_api_guards)

# Collect feature defines that match what edge_veda_static was built with
set(EV_TEST_FEATURE_DEFINES)
if(LLAMA_CPP_AVAILABLE)
    list(APPEND EV_TEST_FEATURE_DEFINES EDGE_VEDA_LLAMA_ENABLED)
endif()
if(WHISPER_CPP_AVAILABLE)
    list(APPEND EV_TEST_FEATURE_DEFINES EDGE_VEDA_WHISPER_ENABLED)
endif()
if(SD_CPP_AVAILABLE)
    list(APPEND EV_TEST_FEATURE_DEFINES EDGE_VEDA_SD_ENABLED)
endif()

# CI-safe memory guard and backend lifecycle unit tests (no model needed)
add_executable(test_memory_guard test_memory_guard.cpp)
target_link_libraries(test_memory_guard PRIVATE edge_veda_static)
target_compile_definitions(test_memory_guard PRIVATE EDGE_VEDA_TEST_HOOKS ${EV_TEST_FEATURE_DEFINES})
target_include_directories(test_memory_guard PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/src
)
set_target_properties(test_memory_guard PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)
add_test(NAME memory_guard COMMAND test_memory_guard)

# CI-safe concurrency regression tests (no model needed)
add_executable(test_concurrency test_concurrency.cpp)
target_link_libraries(test_concurrency PRIVATE edge_veda_static)
target_compile_definitions(test_concurrency PRIVATE EDGE_VEDA_TEST_HOOKS ${EV_TEST_FEATURE_DEFINES})
target_include_directories(test_concurrency PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/src
)
set_target_properties(test_concurrency PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)
add_test(NAME concurrency COMMAND test_concurrency)
set_tests_properties(concurrency PROPERTIES TIMEOUT 30)

# Model-backed tests (require -DEDGE_VEDA_TEST_MODEL_PATH=<path>)
if(DEFINED EDGE_VEDA_TEST_MODEL_PATH AND EXISTS "${EDGE_VEDA_TEST_MODEL_PATH}")
    message(STATUS "Model-backed tests enabled: ${EDGE_VEDA_TEST_MODEL_PATH}")

    add_executable(test_model_backed test_model_backed.cpp)
    target_link_libraries(test_model_backed PRIVATE edge_veda_static)
    target_compile_definitions(test_model_backed PRIVATE
        EDGE_VEDA_TEST_HOOKS
        TEST_MODEL_PATH="${EDGE_VEDA_TEST_MODEL_PATH}"
    )
    target_include_directories(test_model_backed PRIVATE
        ${CMAKE_SOURCE_DIR}/include
    )
    set_target_properties(test_model_backed PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
    )
    add_test(NAME model_backed COMMAND test_model_backed)
    set_tests_properties(model_backed PROPERTIES TIMEOUT 120)
else()
    message(STATUS "Model-backed tests SKIPPED (set -DEDGE_VEDA_TEST_MODEL_PATH=<path>)")
endif()
