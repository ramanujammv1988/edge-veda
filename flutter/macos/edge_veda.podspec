#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'edge_veda'
  s.version          = '2.1.0'
  s.summary          = 'Edge Veda SDK - On-device AI inference for Flutter'
  s.description      = <<-DESC
Edge Veda SDK enables running Large Language Models, Speech-to-Text, and
Text-to-Speech directly on macOS devices with hardware acceleration via Metal.
Features sub-200ms latency, 100% privacy, and zero server costs.
                       DESC
  s.homepage         = 'https://github.com/ramanujammv1988/edge-veda'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Edge Veda' => 'contact@edgeveda.com' }
  s.source           = { :git => 'https://github.com/ramanujammv1988/edge-veda.git', :tag => s.version.to_s }

  # Platform support
  s.platform         = :osx, '11.0'
  s.osx.deployment_target = '11.0'

  # Swift version
  s.swift_version    = '5.0'

  # Source files
  s.source_files     = 'Classes/**/*'

  # Frameworks
  s.frameworks       = 'Metal', 'MetalPerformanceShaders', 'Accelerate', 'AVFoundation', 'Photos', 'EventKit', 'IOKit', 'AppKit'

  # Dependencies
  s.dependency 'FlutterMacOS'

  # Static framework (required for Flutter plugins)
  s.static_framework = true

  # XCFramework path
  s.preserve_paths = 'Frameworks/EdgeVedaCore.xcframework'

  # Libraries
  s.libraries = 'c++'

  # Build settings - export symbols for FFI dlsym access
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
  }

  # Force load the static library so symbols are available for FFI dlsym.
  # macOS always builds native (no simulator variant), so a single force_load path suffices.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => [
      '$(inherited)',
      '-framework Metal', '-framework MetalPerformanceShaders', '-framework Accelerate',
      '-framework IOKit', '-framework AppKit',
      '-force_load "${PODS_ROOT}/../.symlinks/plugins/edge_veda/macos/Frameworks/EdgeVedaCore.xcframework/macos-arm64_x86_64/libedge_veda_full.a"',
      # Xcode 26 debug dylib entry points (required for debug blank executor stub)
      '-Wl,-exported_symbol,_main',
      '-Wl,-exported_symbol,___debug_main_executable_dylib_entry_point',
      # Edge Veda FFI symbols
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
      '-Wl,-u,_ev_vision_get_last_timings', '-Wl,-exported_symbol,_ev_vision_get_last_timings',
      # Whisper STT FFI symbols
      '-Wl,-u,_ev_whisper_config_default', '-Wl,-exported_symbol,_ev_whisper_config_default',
      '-Wl,-u,_ev_whisper_init', '-Wl,-exported_symbol,_ev_whisper_init',
      '-Wl,-u,_ev_whisper_transcribe', '-Wl,-exported_symbol,_ev_whisper_transcribe',
      '-Wl,-u,_ev_whisper_free_result', '-Wl,-exported_symbol,_ev_whisper_free_result',
      '-Wl,-u,_ev_whisper_free', '-Wl,-exported_symbol,_ev_whisper_free',
      '-Wl,-u,_ev_whisper_is_valid', '-Wl,-exported_symbol,_ev_whisper_is_valid',
      # Embedding API
      '-Wl,-u,_ev_embed', '-Wl,-exported_symbol,_ev_embed',
      '-Wl,-u,_ev_free_embeddings', '-Wl,-exported_symbol,_ev_free_embeddings',
      # Streaming confidence
      '-Wl,-u,_ev_stream_get_token_info', '-Wl,-exported_symbol,_ev_stream_get_token_info',
    ].join(' ')
  }
end
