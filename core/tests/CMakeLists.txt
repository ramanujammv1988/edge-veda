# Edge Veda Core Tests
cmake_minimum_required(VERSION 3.15)

# Test inference executable
add_executable(test_inference test_inference.cpp)

target_link_libraries(test_inference PRIVATE edge_veda_static)

target_include_directories(test_inference PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

# Copy test to output directory
set_target_properties(test_inference PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/tests
)
