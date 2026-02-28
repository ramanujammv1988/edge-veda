#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'edge_veda'
  s.version          = '2.4.2'
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

  # Binary Distribution
  #
  # The native C engines (llama.cpp, whisper.cpp, stable-diffusion.cpp) are
  # distributed as a pre-built dynamic XCFramework via the EdgeVedaCore pod.
  # CocoaPods fetches it automatically from GitHub Releases during `pod install`.
  #
  # NOTE: CocoaPods prepare_command does NOT run for Flutter plugins (installed
  # via :path from pub cache). A separate EdgeVedaCore pod with :http source
  # is the only approach that works for pub.dev consumers.
  #
  # For local development: ./scripts/build-ios.sh --clean --release
  s.dependency 'EdgeVedaCore', '~> 2.4'

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
