#!/bin/bash
set -e

# Build Android shared libraries for Edge Veda SDK
# Usage: ./scripts/build-android.sh [--clean] [--release] [--abi <list>]
#
# This script builds shared libraries (.so) for Android using the NDK toolchain.
# It produces per-ABI libedge_veda.so files and packages a jniLibs directory
# ready for Flutter plugin integration.
#
# Default ABIs: arm64-v8a armeabi-v7a x86_64 (matches build.gradle abiFilters)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$PROJECT_ROOT/core"
BUILD_DIR="$PROJECT_ROOT/build/android"
OUTPUT_DIR="$BUILD_DIR/jniLibs"

# Parse arguments
CLEAN=false
BUILD_TYPE="Release"
ABIS="arm64-v8a armeabi-v7a x86_64"

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
        --abi)
            ABIS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--clean] [--debug|--release] [--abi <list>]"
            echo ""
            echo "Options:"
            echo "  --clean    Remove previous build artifacts before building"
            echo "  --debug    Build with debug symbols (default: Release)"
            echo "  --release  Build optimized release binary (default)"
            echo "  --abi      Space-separated list of ABIs (default: arm64-v8a armeabi-v7a x86_64)"
            echo "  -h, --help Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --clean --release"
            echo "  $0 --abi 'arm64-v8a x86_64'"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "=== Edge Veda Android Build ==="
echo "Build type: $BUILD_TYPE"
echo "Target ABIs: $ABIS"
echo "Project root: $PROJECT_ROOT"

# ============================================================================
# Check for required tools
# ============================================================================
check_tools() {
    local missing=0

    if ! command -v cmake &> /dev/null; then
        echo "ERROR: cmake not found. Install cmake for your platform."
        missing=1
    fi

    if ! command -v ninja &> /dev/null; then
        echo "ERROR: ninja not found. Install ninja-build for your platform."
        missing=1
    fi

    # Detect Android NDK
    if [ -n "$ANDROID_NDK_HOME" ]; then
        ANDROID_NDK="$ANDROID_NDK_HOME"
    elif [ -n "$ANDROID_NDK" ]; then
        : # already set
    elif [ -n "$NDK_ROOT" ]; then
        ANDROID_NDK="$NDK_ROOT"
    elif [ -d "$HOME/Android/Sdk/ndk" ]; then
        # Pick the latest installed NDK version
        ANDROID_NDK=$(ls -d "$HOME/Android/Sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        ANDROID_NDK="${ANDROID_NDK%/}"
    elif [ -d "$ANDROID_HOME/ndk" ]; then
        ANDROID_NDK=$(ls -d "$ANDROID_HOME/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        ANDROID_NDK="${ANDROID_NDK%/}"
    fi

    if [ -z "$ANDROID_NDK" ] || [ ! -d "$ANDROID_NDK" ]; then
        echo "ERROR: Android NDK not found."
        echo "Set ANDROID_NDK_HOME, ANDROID_NDK, or NDK_ROOT environment variable."
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        exit 1
    fi

    echo "Android NDK: $ANDROID_NDK"
}

check_tools

# ============================================================================
# Clean if requested
# ============================================================================
if [ "$CLEAN" = true ]; then
    echo "Cleaning previous Android builds..."
    rm -rf "$BUILD_DIR"
fi

# ============================================================================
# Initialize submodules if needed
# ============================================================================
if [ ! -f "$CORE_DIR/third_party/llama.cpp/CMakeLists.txt" ] || \
   [ ! -f "$CORE_DIR/third_party/whisper.cpp/CMakeLists.txt" ] || \
   [ ! -f "$CORE_DIR/third_party/stable-diffusion.cpp/CMakeLists.txt" ]; then
    echo "Initializing git submodules..."
    cd "$PROJECT_ROOT"
    git submodule update --init --recursive
fi

# ============================================================================
# Multi-ABI build loop
# ============================================================================
BUILT_ABIS=()

for abi in $ABIS; do
    echo ""
    echo "=== Building for ABI: $abi ==="

    BUILD_ABI_DIR="$BUILD_DIR/$abi"
    mkdir -p "$BUILD_ABI_DIR"

    cmake -B "$BUILD_ABI_DIR" \
        -S "$CORE_DIR" \
        -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$CORE_DIR/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$abi" \
        -DANDROID_PLATFORM=android-24 \
        -DANDROID_STL=c++_shared \
        -DANDROID_NDK="$ANDROID_NDK" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DEDGE_VEDA_BUILD_SHARED=ON \
        -DEDGE_VEDA_BUILD_STATIC=OFF \
        -DEDGE_VEDA_ENABLE_VULKAN=OFF \
        -DEDGE_VEDA_ENABLE_CPU=ON \
        -DGGML_OPENMP=OFF

    cmake --build "$BUILD_ABI_DIR" --config "$BUILD_TYPE"

    # Find the built shared library
    ABI_LIB=""
    if [ -f "$BUILD_ABI_DIR/libedge_veda.so" ]; then
        ABI_LIB="$BUILD_ABI_DIR/libedge_veda.so"
    elif [ -f "$BUILD_ABI_DIR/$BUILD_TYPE/libedge_veda.so" ]; then
        ABI_LIB="$BUILD_ABI_DIR/$BUILD_TYPE/libedge_veda.so"
    else
        # Fallback: search for the library
        ABI_LIB=$(find "$BUILD_ABI_DIR" -name "libedge_veda.so" 2>/dev/null | head -1)
    fi

    if [ -z "$ABI_LIB" ] || [ ! -f "$ABI_LIB" ]; then
        echo "ERROR: libedge_veda.so not found for ABI $abi"
        echo "Searching for edge_veda files:"
        find "$BUILD_ABI_DIR" -name "*edge_veda*" -ls 2>/dev/null || true
        exit 1
    fi

    echo "Library found: $ABI_LIB"
    echo "Library size: $(du -h "$ABI_LIB" | cut -f1)"

    # Copy to staging directory
    STAGING_DIR="$BUILD_DIR/staging/$abi"
    mkdir -p "$STAGING_DIR"
    cp "$ABI_LIB" "$STAGING_DIR/libedge_veda.so"

    BUILT_ABIS+=("$abi")
done

# ============================================================================
# Library verification
# ============================================================================
echo ""
echo "=== Library Verification ==="
VERIFICATION_FAILED=false

# Determine symbol inspection tool
SYMBOL_TOOL=""
if command -v readelf &> /dev/null; then
    SYMBOL_TOOL="readelf"
elif [ -n "$ANDROID_NDK" ]; then
    # Try NDK's llvm-readelf
    NDK_READELF=$(find "$ANDROID_NDK" -name "llvm-readelf" 2>/dev/null | head -1)
    if [ -n "$NDK_READELF" ] && [ -x "$NDK_READELF" ]; then
        SYMBOL_TOOL="$NDK_READELF"
    fi
fi

# Fall back to nm -D
if [ -z "$SYMBOL_TOOL" ]; then
    if command -v nm &> /dev/null; then
        SYMBOL_TOOL="nm"
    fi
fi

for abi in "${BUILT_ABIS[@]}"; do
    SO_FILE="$BUILD_DIR/staging/$abi/libedge_veda.so"
    echo ""
    echo "--- $abi ---"

    # File size check (warn if > 20MB per ABI)
    SO_SIZE_KB=$(du -k "$SO_FILE" | cut -f1)
    MAX_SIZE_KB=20480  # 20MB
    if [ "$SO_SIZE_KB" -gt "$MAX_SIZE_KB" ]; then
        echo "  WARNING: libedge_veda.so (${SO_SIZE_KB}KB) exceeds 20MB"
    fi
    echo "  Size: ${SO_SIZE_KB}KB (warning threshold: ${MAX_SIZE_KB}KB)"

    # Architecture verification
    echo "  Type: $(file "$SO_FILE" 2>/dev/null | sed 's/.*: //')"

    # Symbol verification
    if [ -n "$SYMBOL_TOOL" ]; then
        if [ "$SYMBOL_TOOL" = "nm" ]; then
            EV_SYMBOLS=$(nm -D "$SO_FILE" 2>/dev/null | grep -c "ev_" || echo "0")
            LLAMA_SYMBOLS=$(nm -D "$SO_FILE" 2>/dev/null | grep -c "llama_" || echo "0")
            WHISPER_SYMBOLS=$(nm -D "$SO_FILE" 2>/dev/null | grep -c "whisper_" || echo "0")
            VISION_SYMBOLS=$(nm -D "$SO_FILE" 2>/dev/null | grep -c "ev_vision_" || echo "0")
            IMAGE_SYMBOLS=$(nm -D "$SO_FILE" 2>/dev/null | grep -c "ev_image_" || echo "0")
        else
            # readelf or llvm-readelf
            EV_SYMBOLS=$("$SYMBOL_TOOL" -Ws "$SO_FILE" 2>/dev/null | grep -c "ev_" || echo "0")
            LLAMA_SYMBOLS=$("$SYMBOL_TOOL" -Ws "$SO_FILE" 2>/dev/null | grep -c "llama_" || echo "0")
            WHISPER_SYMBOLS=$("$SYMBOL_TOOL" -Ws "$SO_FILE" 2>/dev/null | grep -c "whisper_" || echo "0")
            VISION_SYMBOLS=$("$SYMBOL_TOOL" -Ws "$SO_FILE" 2>/dev/null | grep -c "ev_vision_" || echo "0")
            IMAGE_SYMBOLS=$("$SYMBOL_TOOL" -Ws "$SO_FILE" 2>/dev/null | grep -c "ev_image_" || echo "0")
        fi

        echo "  ev_* symbols: $EV_SYMBOLS"
        if [ "$EV_SYMBOLS" -lt 20 ]; then
            echo "  ERROR: Insufficient ev_* symbols (found $EV_SYMBOLS, need >= 20)"
            VERIFICATION_FAILED=true
        fi

        echo "  llama_* symbols: $LLAMA_SYMBOLS"
        if [ "$LLAMA_SYMBOLS" -lt 50 ]; then
            echo "  ERROR: Insufficient llama_* symbols (found $LLAMA_SYMBOLS, need >= 50)"
            VERIFICATION_FAILED=true
        fi

        echo "  whisper_* symbols: $WHISPER_SYMBOLS"
        if [ "$WHISPER_SYMBOLS" -lt 5 ]; then
            echo "  WARNING: Expected at least 5 whisper_* symbols (found $WHISPER_SYMBOLS)"
        fi

        echo "  ev_vision_* symbols: $VISION_SYMBOLS"
        echo "  ev_image_* symbols: $IMAGE_SYMBOLS"
    else
        echo "  WARNING: No symbol inspection tool available (readelf/nm), skipping symbol checks"
    fi
done

if [ "$VERIFICATION_FAILED" = true ]; then
    echo ""
    echo "VERIFICATION FAILED: Required symbols not properly exported"
    exit 1
fi

# ============================================================================
# Package jniLibs directory
# ============================================================================
echo ""
echo "=== Packaging jniLibs ==="

rm -rf "$OUTPUT_DIR"

for abi in "${BUILT_ABIS[@]}"; do
    JNILIB_DIR="$OUTPUT_DIR/$abi"
    mkdir -p "$JNILIB_DIR"

    # Copy libedge_veda.so
    cp "$BUILD_DIR/staging/$abi/libedge_veda.so" "$JNILIB_DIR/"

    # Copy libc++_shared.so from NDK (required since ANDROID_STL=c++_shared)
    # The NDK provides this at: toolchains/llvm/prebuilt/*/sysroot/usr/lib/<triple>/
    TRIPLE=""
    case "$abi" in
        arm64-v8a)    TRIPLE="aarch64-linux-android" ;;
        armeabi-v7a)  TRIPLE="arm-linux-androideabi" ;;
        x86_64)       TRIPLE="x86_64-linux-android" ;;
        x86)          TRIPLE="i686-linux-android" ;;
    esac

    LIBCXX=""
    if [ -n "$TRIPLE" ]; then
        LIBCXX=$(find "$ANDROID_NDK/toolchains/llvm/prebuilt" -path "*/$TRIPLE/libc++_shared.so" 2>/dev/null | head -1)
    fi

    if [ -n "$LIBCXX" ] && [ -f "$LIBCXX" ]; then
        cp "$LIBCXX" "$JNILIB_DIR/"
        echo "  $abi: libedge_veda.so + libc++_shared.so"
    else
        echo "  $abi: libedge_veda.so (WARNING: libc++_shared.so not found in NDK)"
    fi
done

# ============================================================================
# Success summary
# ============================================================================
echo ""
echo "=== Build Complete ==="
echo ""
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Library sizes:"
for abi in "${BUILT_ABIS[@]}"; do
    SO_SIZE=$(du -h "$OUTPUT_DIR/$abi/libedge_veda.so" | cut -f1)
    echo "  $abi/libedge_veda.so: $SO_SIZE"
done

echo ""
echo "jniLibs structure:"
find "$OUTPUT_DIR" -type f -name "*.so" | sort | while read -r f; do
    echo "  ${f#$BUILD_DIR/}"
done

echo ""
echo "=== SUCCESS ==="
echo "jniLibs ready for Flutter integration at:"
echo "  $OUTPUT_DIR"
echo ""
echo "To use in Flutter, copy to flutter/android/src/main/jniLibs/"
echo "  cp -r $OUTPUT_DIR flutter/android/src/main/jniLibs"

echo ""
echo "=== Done ==="
