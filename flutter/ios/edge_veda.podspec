#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'edge_veda'
  s.version          = '0.1.0'
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

  # Vendored libraries - will contain the compiled C++ core
  s.vendored_frameworks = 'Frameworks/EdgeVedaCore.xcframework'

  # Static framework (required for Flutter plugins)
  s.static_framework = true

  # Build settings
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-framework Metal -framework MetalPerformanceShaders -framework Accelerate',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
  }

  # Resource bundles for Metal shaders if needed
  # s.resource_bundles = {
  #   'EdgeVedaResources' => ['Resources/**/*.{metal,metallib}']
  # }
end
