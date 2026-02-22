#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'edge_veda'
  s.version          = '2.3.1'
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
  #
  # The EdgeVedaCore.xcframework (~31MB with llama.cpp + whisper.cpp + sd.cpp)
  # ships as a dynamic framework via vendored_frameworks. This eliminates the
  # need for force_load, exported_symbol whitelists, and use_modular_headers!.
  # The dynamic framework works with both use_frameworks! and use_modular_headers!.
  #
  # The prepare_command auto-downloads the pre-built XCFramework from GitHub
  # Releases when `pod install` runs. This means:
  #   - Users install via `flutter pub add edge_veda` — no manual download needed
  #   - The ~31MB binary stays out of the git repo and pub.dev package
  #   - Developers can still build locally: ./scripts/build-ios.sh --clean --release
  #
  # If the XCFramework already exists (local build), the download is skipped.
  s.prepare_command = <<-SCRIPT
    FRAMEWORK_DIR="Frameworks"
    XCFRAMEWORK="$FRAMEWORK_DIR/EdgeVedaCore.xcframework"

    # Skip download if already present (local build or cached)
    if [ -d "$XCFRAMEWORK" ]; then
      echo "[EdgeVeda] XCFramework already present, skipping download."
      exit 0
    fi

    VERSION="#{s.version}"
    REPO="ramanujammv1988/edge-veda"
    URL="https://github.com/$REPO/releases/download/v$VERSION/EdgeVedaCore.xcframework.zip"

    echo "[EdgeVeda] Downloading EdgeVedaCore.xcframework v$VERSION..."
    mkdir -p "$FRAMEWORK_DIR"

    # Try curl first (available on all macOS), fall back to wget
    if command -v curl >/dev/null 2>&1; then
      HTTP_CODE=$(curl -L -w "%{http_code}" -o "$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip" "$URL" 2>/dev/null)
      if [ "$HTTP_CODE" != "200" ]; then
        rm -f "$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip"
        echo ""
        echo "[EdgeVeda] ERROR: Failed to download XCFramework (HTTP $HTTP_CODE)"
        echo ""
        echo "  The pre-built binary for v$VERSION was not found at:"
        echo "    $URL"
        echo ""
        echo "  Options:"
        echo "    1. Build locally:  ./scripts/build-ios.sh --clean --release"
        echo "    2. Check releases: https://github.com/$REPO/releases"
        echo ""
        exit 1
      fi
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip" "$URL" || {
        rm -f "$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip"
        echo "[EdgeVeda] ERROR: Failed to download XCFramework."
        echo "  Build locally: ./scripts/build-ios.sh --clean --release"
        exit 1
      }
    else
      echo "[EdgeVeda] ERROR: Neither curl nor wget found."
      exit 1
    fi

    # Verify the download is a valid zip
    if ! file "$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip" | grep -q "Zip"; then
      rm -f "$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip"
      echo "[EdgeVeda] ERROR: Downloaded file is not a valid zip archive."
      echo "  Build locally: ./scripts/build-ios.sh --clean --release"
      exit 1
    fi

    echo "[EdgeVeda] Extracting XCFramework..."
    unzip -q -o "$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip" -d "$FRAMEWORK_DIR"
    rm -f "$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip"

    # Handle case where zip contains a top-level directory
    if [ ! -d "$XCFRAMEWORK" ] && [ -d "$FRAMEWORK_DIR/EdgeVedaCore.xcframework" ]; then
      echo "[EdgeVeda] XCFramework extracted successfully."
    elif [ ! -d "$XCFRAMEWORK" ]; then
      # The zip might have a different structure — look for the xcframework
      FOUND=$(find "$FRAMEWORK_DIR" -name "EdgeVedaCore.xcframework" -type d -maxdepth 2 | head -1)
      if [ -n "$FOUND" ] && [ "$FOUND" != "$XCFRAMEWORK" ]; then
        mv "$FOUND" "$XCFRAMEWORK"
      else
        echo "[EdgeVeda] ERROR: XCFramework not found after extraction."
        echo "  Build locally: ./scripts/build-ios.sh --clean --release"
        exit 1
      fi
    fi

    echo "[EdgeVeda] EdgeVedaCore.xcframework v$VERSION ready."
  SCRIPT

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
