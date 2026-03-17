require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "edge-veda"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["repository"]
  s.license      = package["license"]
  s.authors      = "Edge Veda"
  s.source       = { :git => "https://github.com/ramanujammv1988/edge-veda.git", :tag => s.version }

  s.platforms    = { :ios => "15.0" }
  s.source_files = "ios/**/*.{h,m,mm,cpp,swift}"
  s.dependency "React-Core"

  install_modules_dependencies(s)
end
