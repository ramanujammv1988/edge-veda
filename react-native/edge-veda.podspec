require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "edge-veda"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "13.0" }
  s.source       = { :git => "https://github.com/edgeveda/edgeveda-sdk.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  # React Native dependencies
  s.dependency "React-Core"

  # Install all dependencies for New Architecture, but only use them when enabled
  install_modules_dependencies(s)

  # TODO: Add Edge Veda Core iOS framework dependency
  # s.dependency "EdgeVedaCore", "~> 0.1.0"

  # Swift version
  s.swift_version = "5.0"
end
