#!/bin/bash
set -e

# Build iOS XCFramework for Edge Veda SDK
# Usage: ./scripts/build-ios.sh [--clean] [--release]
#
# This script builds static libraries for iOS device (arm64) and simulator (arm64),
# links them into dynamic frameworks, then packages them into an XCFramework for
# Flutter plugin integration via vendored_frameworks.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$PROJECT_ROOT/core"
OUTPUT_DIR="$PROJECT_ROOT/flutter/ios/Frameworks"
BUILD_DIR="$PROJECT_ROOT/build"

# Parse arguments
CLEAN=false
BUILD_TYPE="Release"

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN=true
            shift
            ;;
        --debug)
            BUILD_TYPE="Debug"
            shift
            ;;
        --release)
            BUILD_TYPE="Release"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--clean] [--debug|--release]"
            echo ""
            echo "Options:"
            echo "  --clean    Remove previous build artifacts before building"
            echo "  --debug    Build with debug symbols (default: Release)"
            echo "  --release  Build optimized release binary (default)"
            echo "  -h, --help Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "=== Edge Veda iOS Build ==="
echo "Build type: $BUILD_TYPE"
echo "Project root: $PROJECT_ROOT"

# Check for required tools
check_tools() {
    local missing=0

    if ! command -v cmake &> /dev/null; then
        echo "ERROR: cmake not found. Install with: brew install cmake"
        missing=1
    fi

    if ! command -v xcodebuild &> /dev/null; then
        echo "ERROR: xcodebuild not found. Install Xcode from the App Store."
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

check_tools

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning previous builds..."
    rm -rf "$BUILD_DIR"
    rm -rf "$OUTPUT_DIR/EdgeVedaCore.xcframework"
fi

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Initialize submodules if needed
if [ ! -f "$CORE_DIR/third_party/llama.cpp/CMakeLists.txt" ] || \
   [ ! -f "$CORE_DIR/third_party/whisper.cpp/CMakeLists.txt" ] || \
   [ ! -f "$CORE_DIR/third_party/stable-diffusion.cpp/CMakeLists.txt" ]; then
    echo "Initializing git submodules..."
    cd "$PROJECT_ROOT"
    git submodule update --init --recursive
fi

# Build for iOS Device (arm64)
echo ""
echo "=== Building for iOS Device (arm64) ==="
BUILD_IOS_DEVICE="$BUILD_DIR/ios-device"
mkdir -p "$BUILD_IOS_DEVICE"

cmake -B "$BUILD_IOS_DEVICE" \
    -S "$CORE_DIR" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$CORE_DIR/cmake/ios.toolchain.cmake" \
    -DPLATFORM=OS64 \
    -DDEPLOYMENT_TARGET=13.0 \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DEDGE_VEDA_BUILD_SHARED=OFF \
    -DEDGE_VEDA_BUILD_STATIC=ON \
    -DEDGE_VEDA_ENABLE_METAL=ON

cmake --build "$BUILD_IOS_DEVICE" --config $BUILD_TYPE

# Find the built static library
DEVICE_LIB=""

# Check standard locations (Ninja puts libs at build root or in subdirs)
if [ -f "$BUILD_IOS_DEVICE/libedge_veda.a" ]; then
    DEVICE_LIB="$BUILD_IOS_DEVICE/libedge_veda.a"
elif [ -f "$BUILD_IOS_DEVICE/$BUILD_TYPE/libedge_veda.a" ]; then
    DEVICE_LIB="$BUILD_IOS_DEVICE/$BUILD_TYPE/libedge_veda.a"
# Xcode-style paths
elif [ -f "$BUILD_IOS_DEVICE/$BUILD_TYPE-iphoneos/edge_veda.framework/edge_veda" ]; then
    DEVICE_LIB="$BUILD_IOS_DEVICE/$BUILD_TYPE-iphoneos/edge_veda.framework/edge_veda"
elif [ -f "$BUILD_IOS_DEVICE/$BUILD_TYPE-iphoneos/libedge_veda.a" ]; then
    DEVICE_LIB="$BUILD_IOS_DEVICE/$BUILD_TYPE-iphoneos/libedge_veda.a"
else
    # Fallback: search for any edge_veda library
    DEVICE_LIB=$(find "$BUILD_IOS_DEVICE" \( -name "libedge_veda.a" -o -path "*/edge_veda.framework/edge_veda" \) 2>/dev/null | head -1)
fi

if [ -z "$DEVICE_LIB" ] || [ ! -f "$DEVICE_LIB" ]; then
    echo "ERROR: Device library not found"
    echo "Searching for edge_veda files:"
    find "$BUILD_IOS_DEVICE" -name "*edge_veda*" -ls
    exit 1
fi

echo "Device library: $DEVICE_LIB"
echo "Device library size: $(du -h "$DEVICE_LIB" | cut -f1)"

# Build for iOS Simulator (arm64 for Apple Silicon Macs)
echo ""
echo "=== Building for iOS Simulator (arm64) ==="
BUILD_IOS_SIM="$BUILD_DIR/ios-simulator"
mkdir -p "$BUILD_IOS_SIM"

cmake -B "$BUILD_IOS_SIM" \
    -S "$CORE_DIR" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$CORE_DIR/cmake/ios.toolchain.cmake" \
    -DPLATFORM=SIMULATORARM64 \
    -DDEPLOYMENT_TARGET=13.0 \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DEDGE_VEDA_BUILD_SHARED=OFF \
    -DEDGE_VEDA_BUILD_STATIC=ON \
    -DEDGE_VEDA_ENABLE_METAL=OFF

cmake --build "$BUILD_IOS_SIM" --config $BUILD_TYPE

# Find the built static library
SIM_LIB=""

# Check standard locations (Ninja puts libs at build root or in subdirs)
if [ -f "$BUILD_IOS_SIM/libedge_veda.a" ]; then
    SIM_LIB="$BUILD_IOS_SIM/libedge_veda.a"
elif [ -f "$BUILD_IOS_SIM/$BUILD_TYPE/libedge_veda.a" ]; then
    SIM_LIB="$BUILD_IOS_SIM/$BUILD_TYPE/libedge_veda.a"
# Xcode-style paths
elif [ -f "$BUILD_IOS_SIM/$BUILD_TYPE-iphonesimulator/edge_veda.framework/edge_veda" ]; then
    SIM_LIB="$BUILD_IOS_SIM/$BUILD_TYPE-iphonesimulator/edge_veda.framework/edge_veda"
elif [ -f "$BUILD_IOS_SIM/$BUILD_TYPE-iphonesimulator/libedge_veda.a" ]; then
    SIM_LIB="$BUILD_IOS_SIM/$BUILD_TYPE-iphonesimulator/libedge_veda.a"
else
    SIM_LIB=$(find "$BUILD_IOS_SIM" \( -name "libedge_veda.a" -o -path "*/edge_veda.framework/edge_veda" \) 2>/dev/null | head -1)
fi

if [ -z "$SIM_LIB" ] || [ ! -f "$SIM_LIB" ]; then
    echo "ERROR: Simulator library not found"
    echo "Searching for edge_veda files:"
    find "$BUILD_IOS_SIM" -name "*edge_veda*" -ls
    exit 1
fi

echo "Simulator library: $SIM_LIB"
echo "Simulator library size: $(du -h "$SIM_LIB" | cut -f1)"

# Find llama.cpp, ggml, and whisper.cpp static libraries
echo ""
echo "=== Collecting llama.cpp + whisper.cpp + stable-diffusion.cpp libraries ==="

# Device libs - search in all possible locations
DEVICE_LLAMA_LIB=$(find "$BUILD_IOS_DEVICE" -name "libllama.a" 2>/dev/null | head -1)
DEVICE_GGML_LIB=$(find "$BUILD_IOS_DEVICE" -name "libggml.a" 2>/dev/null | head -1)
DEVICE_GGML_BASE_LIB=$(find "$BUILD_IOS_DEVICE" -name "libggml-base.a" 2>/dev/null | head -1)
DEVICE_GGML_METAL_LIB=$(find "$BUILD_IOS_DEVICE" -name "libggml-metal.a" 2>/dev/null | head -1)
DEVICE_GGML_CPU_LIB=$(find "$BUILD_IOS_DEVICE" -name "libggml-cpu.a" 2>/dev/null | head -1)
DEVICE_GGML_BLAS_LIB=$(find "$BUILD_IOS_DEVICE" -name "libggml-blas.a" 2>/dev/null | head -1)
DEVICE_MTMD_LIB=$(find "$BUILD_IOS_DEVICE" -name "libmtmd.a" 2>/dev/null | head -1)
DEVICE_WHISPER_LIB=$(find "$BUILD_IOS_DEVICE" -name "libwhisper.a" 2>/dev/null | head -1)
DEVICE_SD_LIB=$(find "$BUILD_IOS_DEVICE" -name "libstable-diffusion.a" 2>/dev/null | head -1)

echo "Device llama: $DEVICE_LLAMA_LIB"
echo "Device ggml: $DEVICE_GGML_LIB"
echo "Device ggml-base: $DEVICE_GGML_BASE_LIB"
echo "Device ggml-metal: $DEVICE_GGML_METAL_LIB"
echo "Device ggml-cpu: $DEVICE_GGML_CPU_LIB"
echo "Device ggml-blas: $DEVICE_GGML_BLAS_LIB"
echo "Device mtmd: $DEVICE_MTMD_LIB"
echo "Device whisper: $DEVICE_WHISPER_LIB"
echo "Device stable-diffusion: $DEVICE_SD_LIB"

# Simulator libs - search in all possible locations
SIM_LLAMA_LIB=$(find "$BUILD_IOS_SIM" -name "libllama.a" 2>/dev/null | head -1)
SIM_GGML_LIB=$(find "$BUILD_IOS_SIM" -name "libggml.a" 2>/dev/null | head -1)
SIM_GGML_BASE_LIB=$(find "$BUILD_IOS_SIM" -name "libggml-base.a" 2>/dev/null | head -1)
SIM_GGML_METAL_LIB=$(find "$BUILD_IOS_SIM" -name "libggml-metal.a" 2>/dev/null | head -1)
SIM_GGML_CPU_LIB=$(find "$BUILD_IOS_SIM" -name "libggml-cpu.a" 2>/dev/null | head -1)
SIM_GGML_BLAS_LIB=$(find "$BUILD_IOS_SIM" -name "libggml-blas.a" 2>/dev/null | head -1)
SIM_MTMD_LIB=$(find "$BUILD_IOS_SIM" -name "libmtmd.a" 2>/dev/null | head -1)
SIM_WHISPER_LIB=$(find "$BUILD_IOS_SIM" -name "libwhisper.a" 2>/dev/null | head -1)
SIM_SD_LIB=$(find "$BUILD_IOS_SIM" -name "libstable-diffusion.a" 2>/dev/null | head -1)

echo "Simulator llama: $SIM_LLAMA_LIB"
echo "Simulator ggml: $SIM_GGML_LIB"
echo "Simulator ggml-base: $SIM_GGML_BASE_LIB"
echo "Simulator ggml-metal: $SIM_GGML_METAL_LIB"
echo "Simulator ggml-cpu: $SIM_GGML_CPU_LIB"
echo "Simulator ggml-blas: $SIM_GGML_BLAS_LIB"
echo "Simulator mtmd: $SIM_MTMD_LIB"
echo "Simulator whisper: $SIM_WHISPER_LIB"
echo "Simulator stable-diffusion: $SIM_SD_LIB"

# Merge libraries into single static library per platform
echo ""
echo "=== Merging static libraries ==="

MERGED_DIR="$BUILD_DIR/merged"
mkdir -p "$MERGED_DIR/device" "$MERGED_DIR/simulator"

# Build list of device libraries to merge
DEVICE_LIBS_TO_MERGE="$DEVICE_LIB"
[ -n "$DEVICE_LLAMA_LIB" ] && [ -f "$DEVICE_LLAMA_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_LLAMA_LIB"
[ -n "$DEVICE_GGML_LIB" ] && [ -f "$DEVICE_GGML_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_GGML_LIB"
[ -n "$DEVICE_GGML_BASE_LIB" ] && [ -f "$DEVICE_GGML_BASE_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_GGML_BASE_LIB"
[ -n "$DEVICE_GGML_METAL_LIB" ] && [ -f "$DEVICE_GGML_METAL_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_GGML_METAL_LIB"
[ -n "$DEVICE_GGML_CPU_LIB" ] && [ -f "$DEVICE_GGML_CPU_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_GGML_CPU_LIB"
[ -n "$DEVICE_GGML_BLAS_LIB" ] && [ -f "$DEVICE_GGML_BLAS_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_GGML_BLAS_LIB"
[ -n "$DEVICE_MTMD_LIB" ] && [ -f "$DEVICE_MTMD_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_MTMD_LIB"
[ -n "$DEVICE_WHISPER_LIB" ] && [ -f "$DEVICE_WHISPER_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_WHISPER_LIB"
[ -n "$DEVICE_SD_LIB" ] && [ -f "$DEVICE_SD_LIB" ] && DEVICE_LIBS_TO_MERGE="$DEVICE_LIBS_TO_MERGE $DEVICE_SD_LIB"

# Build list of simulator libraries to merge
SIM_LIBS_TO_MERGE="$SIM_LIB"
[ -n "$SIM_LLAMA_LIB" ] && [ -f "$SIM_LLAMA_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_LLAMA_LIB"
[ -n "$SIM_GGML_LIB" ] && [ -f "$SIM_GGML_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_GGML_LIB"
[ -n "$SIM_GGML_BASE_LIB" ] && [ -f "$SIM_GGML_BASE_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_GGML_BASE_LIB"
[ -n "$SIM_GGML_METAL_LIB" ] && [ -f "$SIM_GGML_METAL_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_GGML_METAL_LIB"
[ -n "$SIM_GGML_CPU_LIB" ] && [ -f "$SIM_GGML_CPU_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_GGML_CPU_LIB"
[ -n "$SIM_GGML_BLAS_LIB" ] && [ -f "$SIM_GGML_BLAS_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_GGML_BLAS_LIB"
[ -n "$SIM_MTMD_LIB" ] && [ -f "$SIM_MTMD_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_MTMD_LIB"
[ -n "$SIM_WHISPER_LIB" ] && [ -f "$SIM_WHISPER_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_WHISPER_LIB"
[ -n "$SIM_SD_LIB" ] && [ -f "$SIM_SD_LIB" ] && SIM_LIBS_TO_MERGE="$SIM_LIBS_TO_MERGE $SIM_SD_LIB"

echo "Merging device libraries: $DEVICE_LIBS_TO_MERGE"
# shellcheck disable=SC2086
libtool -static -o "$MERGED_DIR/device/libedge_veda_full.a" $DEVICE_LIBS_TO_MERGE 2>/dev/null || {
    echo "libtool merge failed for device, using primary library only"
    cp "$DEVICE_LIB" "$MERGED_DIR/device/libedge_veda_full.a"
}

echo "Merging simulator libraries: $SIM_LIBS_TO_MERGE"
# shellcheck disable=SC2086
libtool -static -o "$MERGED_DIR/simulator/libedge_veda_full.a" $SIM_LIBS_TO_MERGE 2>/dev/null || {
    echo "libtool merge failed for simulator, using primary library only"
    cp "$SIM_LIB" "$MERGED_DIR/simulator/libedge_veda_full.a"
}

echo "Merged device library size: $(du -h "$MERGED_DIR/device/libedge_veda_full.a" | cut -f1)"
echo "Merged simulator library size: $(du -h "$MERGED_DIR/simulator/libedge_veda_full.a" | cut -f1)"

# Strip bitcode from libraries (required for xcframework creation)
echo ""
echo "=== Stripping bitcode ==="
if command -v bitcode_strip &> /dev/null || xcrun --find bitcode_strip &> /dev/null; then
    BITCODE_STRIP=$(xcrun --find bitcode_strip 2>/dev/null || echo "bitcode_strip")
    echo "Using: $BITCODE_STRIP"

    "$BITCODE_STRIP" -r "$MERGED_DIR/device/libedge_veda_full.a" -o "$MERGED_DIR/device/libedge_veda_full_stripped.a" 2>/dev/null && \
        mv "$MERGED_DIR/device/libedge_veda_full_stripped.a" "$MERGED_DIR/device/libedge_veda_full.a" && \
        echo "Device library: bitcode stripped" || echo "Device library: no bitcode found or strip failed"

    "$BITCODE_STRIP" -r "$MERGED_DIR/simulator/libedge_veda_full.a" -o "$MERGED_DIR/simulator/libedge_veda_full_stripped.a" 2>/dev/null && \
        mv "$MERGED_DIR/simulator/libedge_veda_full_stripped.a" "$MERGED_DIR/simulator/libedge_veda_full.a" && \
        echo "Simulator library: bitcode stripped" || echo "Simulator library: no bitcode found or strip failed"
else
    echo "WARNING: bitcode_strip not found, xcframework creation may fail"
fi

# Verify library sizes are under 40MB
echo ""
echo "=== Verifying static library sizes ==="
DEVICE_SIZE_KB=$(du -k "$MERGED_DIR/device/libedge_veda_full.a" | cut -f1)
SIM_SIZE_KB=$(du -k "$MERGED_DIR/simulator/libedge_veda_full.a" | cut -f1)
MAX_SIZE_KB=40960  # 40MB (llama.cpp + whisper.cpp + stable-diffusion.cpp)

if [ "$DEVICE_SIZE_KB" -gt "$MAX_SIZE_KB" ]; then
    echo "WARNING: Device library (${DEVICE_SIZE_KB}KB) exceeds 40MB limit"
    echo "Consider enabling LTO or stripping symbols: strip -S libedge_veda_full.a"
fi

if [ "$SIM_SIZE_KB" -gt "$MAX_SIZE_KB" ]; then
    echo "WARNING: Simulator library (${SIM_SIZE_KB}KB) exceeds 40MB limit"
fi

echo "Device: ${DEVICE_SIZE_KB}KB (limit: ${MAX_SIZE_KB}KB)"
echo "Simulator: ${SIM_SIZE_KB}KB (limit: ${MAX_SIZE_KB}KB)"

# Create dynamic frameworks from merged static libraries
echo ""
echo "=== Creating dynamic frameworks ==="

# DEVICE dynamic framework
DEVICE_FW_DIR="$MERGED_DIR/device/EdgeVedaCore.framework"
mkdir -p "$DEVICE_FW_DIR/Headers"
cp "$CORE_DIR/include/edge_veda.h" "$DEVICE_FW_DIR/Headers/"

echo "Linking device dynamic framework..."
clang -dynamiclib -arch arm64 \
    -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
    -miphoneos-version-min=13.0 \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -framework Accelerate \
    -lobjc -lc++ \
    -Wl,-force_load,"$MERGED_DIR/device/libedge_veda_full.a" \
    -install_name @rpath/EdgeVedaCore.framework/EdgeVedaCore \
    -o "$DEVICE_FW_DIR/EdgeVedaCore"

cat > "$DEVICE_FW_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.edgeveda.core</string>
  <key>CFBundleName</key>
  <string>EdgeVedaCore</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleExecutable</key>
  <string>EdgeVedaCore</string>
  <key>MinimumOSVersion</key>
  <string>13.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array><string>iPhoneOS</string></array>
</dict>
</plist>
PLIST

echo "Device framework: $(du -h "$DEVICE_FW_DIR/EdgeVedaCore" | cut -f1)"

# SIMULATOR dynamic framework
SIM_FW_DIR="$MERGED_DIR/simulator/EdgeVedaCore.framework"
mkdir -p "$SIM_FW_DIR/Headers"
cp "$CORE_DIR/include/edge_veda.h" "$SIM_FW_DIR/Headers/"

echo "Linking simulator dynamic framework..."
clang -dynamiclib -arch arm64 \
    -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) \
    -mios-simulator-version-min=13.0 \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -framework Accelerate \
    -lobjc -lc++ \
    -Wl,-force_load,"$MERGED_DIR/simulator/libedge_veda_full.a" \
    -install_name @rpath/EdgeVedaCore.framework/EdgeVedaCore \
    -o "$SIM_FW_DIR/EdgeVedaCore"

cat > "$SIM_FW_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.edgeveda.core</string>
  <key>CFBundleName</key>
  <string>EdgeVedaCore</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleExecutable</key>
  <string>EdgeVedaCore</string>
  <key>MinimumOSVersion</key>
  <string>13.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array><string>iPhoneSimulator</string></array>
</dict>
</plist>
PLIST

echo "Simulator framework: $(du -h "$SIM_FW_DIR/EdgeVedaCore" | cut -f1)"

# Create XCFramework from dynamic frameworks
echo ""
echo "=== Creating XCFramework ==="

# Remove existing XCFramework
rm -rf "$OUTPUT_DIR/EdgeVedaCore.xcframework"

# Create XCFramework with dynamic frameworks
xcodebuild -create-xcframework \
    -framework "$MERGED_DIR/device/EdgeVedaCore.framework" \
    -framework "$MERGED_DIR/simulator/EdgeVedaCore.framework" \
    -output "$OUTPUT_DIR/EdgeVedaCore.xcframework"

# Verify XCFramework
if [ -d "$OUTPUT_DIR/EdgeVedaCore.xcframework" ]; then
    echo ""
    echo "=== Build Complete ==="
    echo "XCFramework created at: $OUTPUT_DIR/EdgeVedaCore.xcframework"
    echo ""
    echo "Contents:"
    ls -la "$OUTPUT_DIR/EdgeVedaCore.xcframework/"
    echo ""

    # Check binary sizes
    echo "Binary sizes:"
    find "$OUTPUT_DIR/EdgeVedaCore.xcframework" -name "EdgeVedaCore" -not -name "*.xcframework" -not -name "*.plist" -exec du -h {} \;

    # Verify architectures
    echo ""
    echo "Architecture verification:"
    for bin in $(find "$OUTPUT_DIR/EdgeVedaCore.xcframework" -name "EdgeVedaCore" -not -name "*.xcframework" -not -name "*.plist"); do
        echo "  $bin:"
        lipo -info "$bin" 2>/dev/null || echo "    (single architecture)"
        file "$bin"
    done

    # Verify symbols are present (CRITICAL)
    echo ""
    echo "=== Symbol verification ==="
    VERIFICATION_FAILED=false
    for bin in $(find "$OUTPUT_DIR/EdgeVedaCore.xcframework" -name "EdgeVedaCore" -not -name "*.xcframework" -not -name "*.plist"); do
        echo ""
        echo "--- $bin ---"

        # Check our C API symbols (ev_*) — these are what Dart FFI binds to
        EV_CORE_SYMBOLS=$(nm "$bin" 2>/dev/null | grep -c " T _ev_" || echo "0")
        echo "  ev_* core symbols: $EV_CORE_SYMBOLS"
        if [ "$EV_CORE_SYMBOLS" -lt 20 ]; then
            echo "  ERROR: Insufficient ev_* symbols (found $EV_CORE_SYMBOLS, need >= 20)"
            VERIFICATION_FAILED=true
        fi

        # Check llama.cpp symbols (C++ mangled in dynamic lib)
        LLAMA_SYMBOLS=$(nm "$bin" 2>/dev/null | grep -c "llama_" || echo "0")
        echo "  llama.cpp symbols (all): $LLAMA_SYMBOLS"
        if [ "$LLAMA_SYMBOLS" -lt 100 ]; then
            echo "  ERROR: Insufficient llama.cpp symbols (found $LLAMA_SYMBOLS, need >= 100)"
            VERIFICATION_FAILED=true
        fi

        # Verify vision symbols (ev_vision_* from vision_engine.cpp + libmtmd)
        VISION_SYMBOLS=$(nm "$bin" 2>/dev/null | grep -c "ev_vision_" || echo "0")
        echo "  ev_vision_* symbols: $VISION_SYMBOLS"
        if [ "$VISION_SYMBOLS" -lt 5 ]; then
            echo "  WARNING: Expected at least 5 ev_vision_* symbols (found $VISION_SYMBOLS)"
        fi

        MTMD_SYMBOLS=$(nm "$bin" 2>/dev/null | grep -c "mtmd_" || echo "0")
        echo "  mtmd_* symbols: $MTMD_SYMBOLS"

        # Verify whisper symbols (whisper_* from libwhisper)
        WHISPER_SYMBOLS=$(nm "$bin" 2>/dev/null | grep -c "whisper_" || echo "0")
        echo "  whisper_* symbols: $WHISPER_SYMBOLS"
        if [ "$WHISPER_SYMBOLS" -lt 5 ]; then
            echo "  WARNING: Expected at least 5 whisper_* symbols (found $WHISPER_SYMBOLS)"
        fi

        # Verify image generation symbols (ev_image_* from image_engine.cpp + libstable-diffusion)
        IMAGE_SYMBOLS=$(nm "$bin" 2>/dev/null | grep -c "ev_image_" || echo "0")
        echo "  ev_image_* symbols: $IMAGE_SYMBOLS"
        if [ "$IMAGE_SYMBOLS" -lt 5 ]; then
            echo "  WARNING: Expected at least 5 ev_image_* symbols (found $IMAGE_SYMBOLS)"
        fi

        # Verify NO duplicate ggml symbols (critical: shared ggml, not duplicated)
        GGML_DUP_CHECK=$(nm "$bin" 2>/dev/null | grep " T " | grep "ggml_" | sort | uniq -d | wc -l | tr -d ' ')
        if [ "$GGML_DUP_CHECK" -gt 0 ]; then
            echo "  ERROR: Duplicate ggml symbols detected ($GGML_DUP_CHECK duplicates)"
            VERIFICATION_FAILED=true
        else
            echo "  No duplicate ggml symbols (shared ggml working correctly)"
        fi
    done

    if [ "$VERIFICATION_FAILED" = true ]; then
        echo ""
        echo "VERIFICATION FAILED: symbols not properly linked"
        exit 1
    fi

    echo ""
    echo "=== SUCCESS ==="
    echo "XCFramework ready for Flutter integration at:"
    echo "  $OUTPUT_DIR/EdgeVedaCore.xcframework"
else
    echo "ERROR: XCFramework creation failed"
    exit 1
fi

echo ""
echo "=== Done ==="
