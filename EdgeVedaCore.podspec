Pod::Spec.new do |s|
  s.name             = 'EdgeVedaCore'
  s.version          = '2.3.1'
  s.summary          = 'On-device AI inference engine for Edge Veda SDK'
  s.description      = <<-DESC
    Pre-built dynamic XCFramework containing llama.cpp, whisper.cpp, and
    stable-diffusion.cpp with Metal GPU acceleration for iOS. This pod is
    consumed by the edge_veda Flutter plugin — not intended for direct use.
  DESC
  s.homepage         = 'https://github.com/ramanujammv1988/edge-veda'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'Edge Veda' => 'contact@edgeveda.com' }

  # The XCFramework is hosted as a GitHub Release asset.
  # CocoaPods downloads and extracts it automatically during `pod install`.
  s.source           = {
    :http => "https://github.com/ramanujammv1988/edge-veda/releases/download/v#{s.version}/EdgeVedaCore.xcframework.zip",
    :type => 'zip'
  }

  s.platform              = :ios, '13.0'
  s.ios.deployment_target  = '13.0'

  # The zip contains EdgeVedaCore.xcframework/ at root level.
  s.vendored_frameworks   = 'EdgeVedaCore.xcframework'

  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
