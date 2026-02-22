#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'edge_veda'
  s.version          = '2.4.0'
  s.summary          = 'Edge Veda SDK - On-device AI inference for Flutter'
  s.description      = <<-DESC
Edge Veda SDK enables running Large Language Models, Speech-to-Text, and
Text-to-Speech directly on iOS devices with hardware acceleration via Metal.
Features sub-200ms latency, 100% privacy, and zero server costs.
                       DESC
  s.homepage         = 'https://github.com/ramanujammv1988/edge-veda'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Edge Veda' => 'contact@edgeveda.com' }
  s.source           = { :git => 'https://github.com/ramanujammv1988/edge-veda.git', :tag => s.version.to_s }

  # Platform support
  s.platform         = :ios, '13.0'
  s.ios.deployment_target = '13.0'

  # Swift/Objective-C version
  s.swift_version    = '5.0'

  # Source files
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  # XCFramework Distribution Strategy
  # The EdgeVedaCore.xcframework (~31MB with llama.cpp + whisper.cpp + sd.cpp)
  # ships as a dynamic framework via vendored_frameworks. This eliminates the
  # need for force_load, exported_symbol whitelists, and use_modular_headers!.
  # The dynamic framework works with both use_frameworks! and use_modular_headers!.
  #
  # Build locally: ./scripts/build-ios.sh --clean --release
  # Or download from GitHub Releases.
  s.vendored_frameworks = 'Frameworks/EdgeVedaCore.xcframework'

  # Frameworks used by the ObjC plugin classes (not the C engine — those are
  # linked into the dynamic framework itself)
  s.frameworks       = 'AVFoundation', 'Photos', 'EventKit'

  # Dependencies
  s.dependency 'Flutter'

  # Build settings
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
  }
end
