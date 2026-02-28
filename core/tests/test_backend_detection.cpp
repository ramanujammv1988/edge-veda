#include "edge_veda.h"
#include <cassert>
#include <iostream>
#include <cstring>

/**
 * Static verification test for Edge Veda C API contracts.
 *
 * This test validates that the C API that the JNI bridge depends on
 * is correctly defined and provides sensible defaults. This is a
 * compile-time and basic runtime verification - NOT a full Android test.
 *
 * Purpose: Prove the C API contracts exist before attempting NDK compilation.
 */

void test_config_defaults() {
  std::cout << "Testing ev_config_default()..." << std::endl;

  ev_config config;
  // Initialize to garbage values to ensure ev_config_default actually sets them
  memset(&config, 0xFF, sizeof(config));

  ev_config_default(&config);

  // Verify default config has sensible values
  assert(config.context_size > 0 && "context_size must be positive");
  assert(config.batch_size > 0 && "batch_size must be positive");
  assert(config.num_threads >= 0 && "num_threads must be non-negative (0=auto)");
  assert(config.gpu_layers >= -1 && "gpu_layers must be >= -1");

  std::cout << "  Default context_size: " << config.context_size << std::endl;
  std::cout << "  Default batch_size: " << config.batch_size << std::endl;
  std::cout << "  Default num_threads: " << config.num_threads << " (0=auto)" << std::endl;
  std::cout << "  Default gpu_layers: " << config.gpu_layers << std::endl;
  std::cout << "PASS: ev_config_default() produces valid defaults" << std::endl;
}

void test_backend_enum() {
  std::cout << "\nTesting backend enum constants..." << std::endl;

  // Verify backend enum constants are defined
  ev_backend_t cpu_backend = EV_BACKEND_CPU;
  ev_backend_t metal_backend = EV_BACKEND_METAL;
  ev_backend_t vulkan_backend = EV_BACKEND_VULKAN;
  ev_backend_t auto_backend = EV_BACKEND_AUTO;

  // Verify they have distinct values
  assert(cpu_backend == 3 && "EV_BACKEND_CPU must be 3");
  assert(metal_backend == 1 && "EV_BACKEND_METAL must be 1");
  assert(vulkan_backend == 2 && "EV_BACKEND_VULKAN must be 2");
  assert(auto_backend == 0 && "EV_BACKEND_AUTO must be 0");

  std::cout << "  EV_BACKEND_CPU = " << cpu_backend << std::endl;
  std::cout << "  EV_BACKEND_METAL = " << metal_backend << std::endl;
  std::cout << "  EV_BACKEND_VULKAN = " << vulkan_backend << std::endl;
  std::cout << "  EV_BACKEND_AUTO = " << auto_backend << std::endl;
  std::cout << "PASS: Backend enum constants are correctly defined" << std::endl;
}

void test_backend_names() {
  std::cout << "\nTesting ev_backend_name()..." << std::endl;

  const char* cpu_name = ev_backend_name(EV_BACKEND_CPU);
  const char* metal_name = ev_backend_name(EV_BACKEND_METAL);
  const char* vulkan_name = ev_backend_name(EV_BACKEND_VULKAN);
  const char* auto_name = ev_backend_name(EV_BACKEND_AUTO);

  assert(cpu_name != nullptr && "CPU backend name must not be NULL");
  assert(metal_name != nullptr && "Metal backend name must not be NULL");
  assert(vulkan_name != nullptr && "Vulkan backend name must not be NULL");
  assert(auto_name != nullptr && "Auto backend name must not be NULL");

  std::cout << "  CPU: " << cpu_name << std::endl;
  std::cout << "  Metal: " << metal_name << std::endl;
  std::cout << "  Vulkan: " << vulkan_name << std::endl;
  std::cout << "  Auto: " << auto_name << std::endl;
  std::cout << "PASS: Backend names are defined" << std::endl;
}

void test_error_strings() {
  std::cout << "\nTesting ev_error_string()..." << std::endl;

  const char* success = ev_error_string(EV_SUCCESS);
  const char* invalid_param = ev_error_string(EV_ERROR_INVALID_PARAM);
  const char* out_of_memory = ev_error_string(EV_ERROR_OUT_OF_MEMORY);

  assert(success != nullptr && "Success error string must not be NULL");
  assert(invalid_param != nullptr && "Invalid param error string must not be NULL");
  assert(out_of_memory != nullptr && "OOM error string must not be NULL");

  std::cout << "  EV_SUCCESS: " << success << std::endl;
  std::cout << "  EV_ERROR_INVALID_PARAM: " << invalid_param << std::endl;
  std::cout << "  EV_ERROR_OUT_OF_MEMORY: " << out_of_memory << std::endl;
  std::cout << "PASS: Error strings are defined" << std::endl;
}

void test_version() {
  std::cout << "\nTesting ev_version()..." << std::endl;

  const char* version = ev_version();
  assert(version != nullptr && "Version string must not be NULL");
  assert(strlen(version) > 0 && "Version string must not be empty");

  std::cout << "  Edge Veda version: " << version << std::endl;
  std::cout << "PASS: Version string is defined" << std::endl;
}

int main() {
  std::cout << "=== Edge Veda C API Static Verification Test ===" << std::endl;
  std::cout << "Purpose: Validate C API contracts that JNI bridge depends on\n" << std::endl;

  try {
    test_version();
    test_config_defaults();
    test_backend_enum();
    test_backend_names();
    test_error_strings();

    std::cout << "\n=== ALL TESTS PASSED ===" << std::endl;
    std::cout << "The C API contracts are correctly defined and provide sensible defaults." << std::endl;
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "\n!!! TEST FAILED !!!" << std::endl;
    std::cerr << "Exception: " << e.what() << std::endl;
    return 1;
  } catch (...) {
    std::cerr << "\n!!! TEST FAILED !!!" << std::endl;
    std::cerr << "Unknown exception caught" << std::endl;
    return 1;
  }
}
