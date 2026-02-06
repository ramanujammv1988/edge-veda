#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'edge_veda'
  s.version          = '1.0.0'
  s.summary          = 'Edge Veda SDK - On-device AI inference for Flutter'
  s.description      = <<-DESC
Edge Veda SDK enables running Large Language Models, Speech-to-Text, and
Text-to-Speech directly on iOS devices with hardware acceleration via Metal.
Features sub-200ms latency, 100% privacy, and zero server costs.
                       DESC
  s.homepage         = 'https://github.com/edgeveda/edge-veda-sdk'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Edge Veda' => 'contact@edgeveda.com' }
  s.source           = { :git => 'https://github.com/edgeveda/edge-veda-sdk.git', :tag => s.version.to_s }

  # Platform support
  s.platform         = :ios, '13.0'
  s.ios.deployment_target = '13.0'

  # Swift/Objective-C version
  s.swift_version    = '5.0'

  # Source files
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  # Frameworks
  s.frameworks       = 'Metal', 'MetalPerformanceShaders', 'Accelerate'

  # Dependencies
  s.dependency 'Flutter'

  # Static framework (required for Flutter plugins)
  s.static_framework = true

  # Keep xcframework path preserved (linked via force_load, not vendored_frameworks)
  #
  # XCFramework Distribution Strategy
  # The EdgeVedaCore.xcframework (~20MB with llama.cpp) exceeds pub.dev's 100MB package limit.
  # For v1.0.0, we use CocoaPods HTTP source approach:
  #   1. XCFramework hosted on GitHub Releases
  #   2. Users download via: curl -L https://github.com/edgeveda/edge-veda-sdk/releases/download/v1.0.0/EdgeVedaCore-ios.xcframework.zip
  #   3. Extract to flutter/ios/Frameworks/ before pod install
  #   4. OR run: ./scripts/build-ios.sh --clean --release
  # Future: Migrate to Dart Native Assets (hook/build.dart) for automatic download in v1.1.0
  #
  s.preserve_paths = 'Frameworks/EdgeVedaCore.xcframework'

  # Libraries
  s.libraries = 'c++'

  # Build settings - export symbols for FFI dlsym access
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
  }

  # Force load the static library into the main app binary so symbols are available for FFI dlsym
  # Use absolute path for force_load to avoid BUILD_DIR mismatch issues
  # Use BOTH -u (to force inclusion) AND -exported_symbol (to keep global visibility for dlsym)
  # Without -exported_symbol, the linker marks symbols as local (t) instead of global (T)
  #
  # Note: We use conditional force_load based on SDK to support both device and simulator builds.
  # The xcframework contains ios-arm64 for device and ios-arm64-simulator for simulator.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS[sdk=iphoneos*]' => [
      '$(inherited)',
      '-framework Metal', '-framework MetalPerformanceShaders', '-framework Accelerate',
      '-force_load "${PODS_ROOT}/../.symlinks/plugins/edge_veda/ios/Frameworks/EdgeVedaCore.xcframework/ios-arm64/libedge_veda_full.a"',
      '-Wl,-u,_ev_version', '-Wl,-exported_symbol,_ev_version',
      '-Wl,-u,_ev_init', '-Wl,-exported_symbol,_ev_init',
      '-Wl,-u,_ev_free', '-Wl,-exported_symbol,_ev_free',
      '-Wl,-u,_ev_is_valid', '-Wl,-exported_symbol,_ev_is_valid',
      '-Wl,-u,_ev_generate', '-Wl,-exported_symbol,_ev_generate',
      '-Wl,-u,_ev_generate_stream', '-Wl,-exported_symbol,_ev_generate_stream',
      '-Wl,-u,_ev_stream_next', '-Wl,-exported_symbol,_ev_stream_next',
      '-Wl,-u,_ev_stream_has_next', '-Wl,-exported_symbol,_ev_stream_has_next',
      '-Wl,-u,_ev_stream_cancel', '-Wl,-exported_symbol,_ev_stream_cancel',
      '-Wl,-u,_ev_stream_free', '-Wl,-exported_symbol,_ev_stream_free',
      '-Wl,-u,_ev_config_default', '-Wl,-exported_symbol,_ev_config_default',
      '-Wl,-u,_ev_generation_params_default', '-Wl,-exported_symbol,_ev_generation_params_default',
      '-Wl,-u,_ev_error_string', '-Wl,-exported_symbol,_ev_error_string',
      '-Wl,-u,_ev_get_last_error', '-Wl,-exported_symbol,_ev_get_last_error',
      '-Wl,-u,_ev_backend_name', '-Wl,-exported_symbol,_ev_backend_name',
      '-Wl,-u,_ev_detect_backend', '-Wl,-exported_symbol,_ev_detect_backend',
      '-Wl,-u,_ev_is_backend_available', '-Wl,-exported_symbol,_ev_is_backend_available',
      '-Wl,-u,_ev_get_memory_usage', '-Wl,-exported_symbol,_ev_get_memory_usage',
      '-Wl,-u,_ev_set_memory_limit', '-Wl,-exported_symbol,_ev_set_memory_limit',
      '-Wl,-u,_ev_set_memory_pressure_callback', '-Wl,-exported_symbol,_ev_set_memory_pressure_callback',
      '-Wl,-u,_ev_memory_cleanup', '-Wl,-exported_symbol,_ev_memory_cleanup',
      '-Wl,-u,_ev_get_model_info', '-Wl,-exported_symbol,_ev_get_model_info',
      '-Wl,-u,_ev_set_verbose', '-Wl,-exported_symbol,_ev_set_verbose',
      '-Wl,-u,_ev_reset', '-Wl,-exported_symbol,_ev_reset',
      '-Wl,-u,_ev_free_string', '-Wl,-exported_symbol,_ev_free_string',
      '-Wl,-u,_ev_vision_init', '-Wl,-exported_symbol,_ev_vision_init',
      '-Wl,-u,_ev_vision_describe', '-Wl,-exported_symbol,_ev_vision_describe',
      '-Wl,-u,_ev_vision_free', '-Wl,-exported_symbol,_ev_vision_free',
      '-Wl,-u,_ev_vision_is_valid', '-Wl,-exported_symbol,_ev_vision_is_valid',
      '-Wl,-u,_ev_vision_config_default', '-Wl,-exported_symbol,_ev_vision_config_default',
    ].join(' '),
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' => [
      '$(inherited)',
      '-framework Metal', '-framework MetalPerformanceShaders', '-framework Accelerate',
      '-force_load "${PODS_ROOT}/../.symlinks/plugins/edge_veda/ios/Frameworks/EdgeVedaCore.xcframework/ios-arm64-simulator/libedge_veda_full.a"',
      '-Wl,-u,_ev_version', '-Wl,-exported_symbol,_ev_version',
      '-Wl,-u,_ev_init', '-Wl,-exported_symbol,_ev_init',
      '-Wl,-u,_ev_free', '-Wl,-exported_symbol,_ev_free',
      '-Wl,-u,_ev_is_valid', '-Wl,-exported_symbol,_ev_is_valid',
      '-Wl,-u,_ev_generate', '-Wl,-exported_symbol,_ev_generate',
      '-Wl,-u,_ev_generate_stream', '-Wl,-exported_symbol,_ev_generate_stream',
      '-Wl,-u,_ev_stream_next', '-Wl,-exported_symbol,_ev_stream_next',
      '-Wl,-u,_ev_stream_has_next', '-Wl,-exported_symbol,_ev_stream_has_next',
      '-Wl,-u,_ev_stream_cancel', '-Wl,-exported_symbol,_ev_stream_cancel',
      '-Wl,-u,_ev_stream_free', '-Wl,-exported_symbol,_ev_stream_free',
      '-Wl,-u,_ev_config_default', '-Wl,-exported_symbol,_ev_config_default',
      '-Wl,-u,_ev_generation_params_default', '-Wl,-exported_symbol,_ev_generation_params_default',
      '-Wl,-u,_ev_error_string', '-Wl,-exported_symbol,_ev_error_string',
      '-Wl,-u,_ev_get_last_error', '-Wl,-exported_symbol,_ev_get_last_error',
      '-Wl,-u,_ev_backend_name', '-Wl,-exported_symbol,_ev_backend_name',
      '-Wl,-u,_ev_detect_backend', '-Wl,-exported_symbol,_ev_detect_backend',
      '-Wl,-u,_ev_is_backend_available', '-Wl,-exported_symbol,_ev_is_backend_available',
      '-Wl,-u,_ev_get_memory_usage', '-Wl,-exported_symbol,_ev_get_memory_usage',
      '-Wl,-u,_ev_set_memory_limit', '-Wl,-exported_symbol,_ev_set_memory_limit',
      '-Wl,-u,_ev_set_memory_pressure_callback', '-Wl,-exported_symbol,_ev_set_memory_pressure_callback',
      '-Wl,-u,_ev_memory_cleanup', '-Wl,-exported_symbol,_ev_memory_cleanup',
      '-Wl,-u,_ev_get_model_info', '-Wl,-exported_symbol,_ev_get_model_info',
      '-Wl,-u,_ev_set_verbose', '-Wl,-exported_symbol,_ev_set_verbose',
      '-Wl,-u,_ev_reset', '-Wl,-exported_symbol,_ev_reset',
      '-Wl,-u,_ev_free_string', '-Wl,-exported_symbol,_ev_free_string',
      '-Wl,-u,_ev_vision_init', '-Wl,-exported_symbol,_ev_vision_init',
      '-Wl,-u,_ev_vision_describe', '-Wl,-exported_symbol,_ev_vision_describe',
      '-Wl,-u,_ev_vision_free', '-Wl,-exported_symbol,_ev_vision_free',
      '-Wl,-u,_ev_vision_is_valid', '-Wl,-exported_symbol,_ev_vision_is_valid',
      '-Wl,-u,_ev_vision_config_default', '-Wl,-exported_symbol,_ev_vision_config_default',
    ].join(' ')
  }

  # Resource bundles for Metal shaders if needed
  # s.resource_bundles = {
  #   'EdgeVedaResources' => ['Resources/**/*.{metal,metallib}']
  # }
end
