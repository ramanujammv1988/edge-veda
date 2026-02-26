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

target_include_directories(test_api_guards PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

set_target_properties(test_api_guards PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)

# ctest discovery
add_test(NAME api_guards COMMAND test_api_guards)
