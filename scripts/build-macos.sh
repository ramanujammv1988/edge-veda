#!/bin/bash
set -e

# Build macOS XCFramework for Edge Veda SDK
# Usage: ./scripts/build-macos.sh [--clean] [--release]
#
# This script builds static libraries for macOS (arm64 and x86_64),
# merges them into a universal binary, then packages into an XCFramework
# for Flutter plugin integration.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$PROJECT_ROOT/core"
OUTPUT_DIR="$PROJECT_ROOT/flutter/macos/Frameworks"
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

echo "=== Edge Veda macOS Build ==="
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
    rm -rf "$BUILD_DIR/macos-arm64"
    rm -rf "$BUILD_DIR/macos-x86_64"
    rm -rf "$BUILD_DIR/macos-merged"
    rm -rf "$OUTPUT_DIR/EdgeVedaCore.xcframework"
fi

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Initialize submodules if needed
if [ ! -f "$CORE_DIR/third_party/llama.cpp/CMakeLists.txt" ] || [ ! -f "$CORE_DIR/third_party/whisper.cpp/CMakeLists.txt" ]; then
    echo "Initializing git submodules..."
    cd "$PROJECT_ROOT"
    git submodule update --init --recursive
fi

# ============================================================================
# Build for macOS arm64 (Apple Silicon)
# ============================================================================
echo ""
echo "=== Building for macOS arm64 (Apple Silicon) ==="
BUILD_MACOS_ARM64="$BUILD_DIR/macos-arm64"
mkdir -p "$BUILD_MACOS_ARM64"

cmake -B "$BUILD_MACOS_ARM64" \
    -S "$CORE_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DEDGE_VEDA_BUILD_SHARED=OFF \
    -DEDGE_VEDA_BUILD_STATIC=ON \
    -DEDGE_VEDA_ENABLE_METAL=ON

cmake --build "$BUILD_MACOS_ARM64" --config $BUILD_TYPE

# Find arm64 library
ARM64_LIB=""
if [ -f "$BUILD_MACOS_ARM64/libedge_veda.a" ]; then
    ARM64_LIB="$BUILD_MACOS_ARM64/libedge_veda.a"
elif [ -f "$BUILD_MACOS_ARM64/$BUILD_TYPE/libedge_veda.a" ]; then
    ARM64_LIB="$BUILD_MACOS_ARM64/$BUILD_TYPE/libedge_veda.a"
else
    ARM64_LIB=$(find "$BUILD_MACOS_ARM64" -name "libedge_veda.a" 2>/dev/null | head -1)
fi

if [ -z "$ARM64_LIB" ] || [ ! -f "$ARM64_LIB" ]; then
    echo "ERROR: arm64 library not found"
    find "$BUILD_MACOS_ARM64" -name "*edge_veda*" -ls
    exit 1
fi

echo "arm64 library: $ARM64_LIB"
echo "arm64 library size: $(du -h "$ARM64_LIB" | cut -f1)"

# ============================================================================
# Build for macOS x86_64 (Intel)
# ============================================================================
echo ""
echo "=== Building for macOS x86_64 (Intel) ==="
BUILD_MACOS_X86="$BUILD_DIR/macos-x86_64"
mkdir -p "$BUILD_MACOS_X86"

cmake -B "$BUILD_MACOS_X86" \
    -S "$CORE_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DEDGE_VEDA_BUILD_SHARED=OFF \
    -DEDGE_VEDA_BUILD_STATIC=ON \
    -DEDGE_VEDA_ENABLE_METAL=ON

cmake --build "$BUILD_MACOS_X86" --config $BUILD_TYPE

# Find x86_64 library
X86_LIB=""
if [ -f "$BUILD_MACOS_X86/libedge_veda.a" ]; then
    X86_LIB="$BUILD_MACOS_X86/libedge_veda.a"
elif [ -f "$BUILD_MACOS_X86/$BUILD_TYPE/libedge_veda.a" ]; then
    X86_LIB="$BUILD_MACOS_X86/$BUILD_TYPE/libedge_veda.a"
else
    X86_LIB=$(find "$BUILD_MACOS_X86" -name "libedge_veda.a" 2>/dev/null | head -1)
fi

if [ -z "$X86_LIB" ] || [ ! -f "$X86_LIB" ]; then
    echo "ERROR: x86_64 library not found"
    find "$BUILD_MACOS_X86" -name "*edge_veda*" -ls
    exit 1
fi

echo "x86_64 library: $X86_LIB"
echo "x86_64 library size: $(du -h "$X86_LIB" | cut -f1)"

# ============================================================================
# Find and merge dependency libraries
# ============================================================================
echo ""
echo "=== Collecting llama.cpp + whisper.cpp libraries ==="

# arm64 dependency libs
ARM64_LLAMA_LIB=$(find "$BUILD_MACOS_ARM64" -name "libllama.a" 2>/dev/null | head -1)
ARM64_GGML_LIB=$(find "$BUILD_MACOS_ARM64" -name "libggml.a" 2>/dev/null | head -1)
ARM64_GGML_BASE_LIB=$(find "$BUILD_MACOS_ARM64" -name "libggml-base.a" 2>/dev/null | head -1)
ARM64_GGML_METAL_LIB=$(find "$BUILD_MACOS_ARM64" -name "libggml-metal.a" 2>/dev/null | head -1)
ARM64_GGML_CPU_LIB=$(find "$BUILD_MACOS_ARM64" -name "libggml-cpu.a" 2>/dev/null | head -1)
ARM64_GGML_BLAS_LIB=$(find "$BUILD_MACOS_ARM64" -name "libggml-blas.a" 2>/dev/null | head -1)
ARM64_MTMD_LIB=$(find "$BUILD_MACOS_ARM64" -name "libmtmd.a" 2>/dev/null | head -1)
ARM64_WHISPER_LIB=$(find "$BUILD_MACOS_ARM64" -name "libwhisper.a" 2>/dev/null | head -1)

echo "arm64 llama: $ARM64_LLAMA_LIB"
echo "arm64 ggml: $ARM64_GGML_LIB"
echo "arm64 ggml-base: $ARM64_GGML_BASE_LIB"
echo "arm64 ggml-metal: $ARM64_GGML_METAL_LIB"
echo "arm64 ggml-cpu: $ARM64_GGML_CPU_LIB"
echo "arm64 ggml-blas: $ARM64_GGML_BLAS_LIB"
echo "arm64 mtmd: $ARM64_MTMD_LIB"
echo "arm64 whisper: $ARM64_WHISPER_LIB"

# x86_64 dependency libs
X86_LLAMA_LIB=$(find "$BUILD_MACOS_X86" -name "libllama.a" 2>/dev/null | head -1)
X86_GGML_LIB=$(find "$BUILD_MACOS_X86" -name "libggml.a" 2>/dev/null | head -1)
X86_GGML_BASE_LIB=$(find "$BUILD_MACOS_X86" -name "libggml-base.a" 2>/dev/null | head -1)
X86_GGML_METAL_LIB=$(find "$BUILD_MACOS_X86" -name "libggml-metal.a" 2>/dev/null | head -1)
X86_GGML_CPU_LIB=$(find "$BUILD_MACOS_X86" -name "libggml-cpu.a" 2>/dev/null | head -1)
X86_GGML_BLAS_LIB=$(find "$BUILD_MACOS_X86" -name "libggml-blas.a" 2>/dev/null | head -1)
X86_MTMD_LIB=$(find "$BUILD_MACOS_X86" -name "libmtmd.a" 2>/dev/null | head -1)
X86_WHISPER_LIB=$(find "$BUILD_MACOS_X86" -name "libwhisper.a" 2>/dev/null | head -1)

echo "x86_64 llama: $X86_LLAMA_LIB"
echo "x86_64 ggml: $X86_GGML_LIB"
echo "x86_64 ggml-base: $X86_GGML_BASE_LIB"
echo "x86_64 ggml-metal: $X86_GGML_METAL_LIB"
echo "x86_64 ggml-cpu: $X86_GGML_CPU_LIB"
echo "x86_64 ggml-blas: $X86_GGML_BLAS_LIB"
echo "x86_64 mtmd: $X86_MTMD_LIB"
echo "x86_64 whisper: $X86_WHISPER_LIB"

# ============================================================================
# Merge static libraries per architecture
# ============================================================================
echo ""
echo "=== Merging static libraries ==="

MERGED_DIR="$BUILD_DIR/macos-merged"
mkdir -p "$MERGED_DIR/arm64" "$MERGED_DIR/x86_64"

# Build arm64 merge list
ARM64_LIBS_TO_MERGE="$ARM64_LIB"
[ -n "$ARM64_LLAMA_LIB" ] && [ -f "$ARM64_LLAMA_LIB" ] && ARM64_LIBS_TO_MERGE="$ARM64_LIBS_TO_MERGE $ARM64_LLAMA_LIB"
[ -n "$ARM64_GGML_LIB" ] && [ -f "$ARM64_GGML_LIB" ] && ARM64_LIBS_TO_MERGE="$ARM64_LIBS_TO_MERGE $ARM64_GGML_LIB"
[ -n "$ARM64_GGML_BASE_LIB" ] && [ -f "$ARM64_GGML_BASE_LIB" ] && ARM64_LIBS_TO_MERGE="$ARM64_LIBS_TO_MERGE $ARM64_GGML_BASE_LIB"
[ -n "$ARM64_GGML_METAL_LIB" ] && [ -f "$ARM64_GGML_METAL_LIB" ] && ARM64_LIBS_TO_MERGE="$ARM64_LIBS_TO_MERGE $ARM64_GGML_METAL_LIB"
[ -n "$ARM64_GGML_CPU_LIB" ] && [ -f "$ARM64_GGML_CPU_LIB" ] && ARM64_LIBS_TO_MERGE="$ARM64_LIBS_TO_MERGE $ARM64_GGML_CPU_LIB"
[ -n "$ARM64_GGML_BLAS_LIB" ] && [ -f "$ARM64_GGML_BLAS_LIB" ] && ARM64_LIBS_TO_MERGE="$ARM64_LIBS_TO_MERGE $ARM64_GGML_BLAS_LIB"
[ -n "$ARM64_MTMD_LIB" ] && [ -f "$ARM64_MTMD_LIB" ] && ARM64_LIBS_TO_MERGE="$ARM64_LIBS_TO_MERGE $ARM64_MTMD_LIB"
[ -n "$ARM64_WHISPER_LIB" ] && [ -f "$ARM64_WHISPER_LIB" ] && ARM64_LIBS_TO_MERGE="$ARM64_LIBS_TO_MERGE $ARM64_WHISPER_LIB"

# Build x86_64 merge list
X86_LIBS_TO_MERGE="$X86_LIB"
[ -n "$X86_LLAMA_LIB" ] && [ -f "$X86_LLAMA_LIB" ] && X86_LIBS_TO_MERGE="$X86_LIBS_TO_MERGE $X86_LLAMA_LIB"
[ -n "$X86_GGML_LIB" ] && [ -f "$X86_GGML_LIB" ] && X86_LIBS_TO_MERGE="$X86_LIBS_TO_MERGE $X86_GGML_LIB"
[ -n "$X86_GGML_BASE_LIB" ] && [ -f "$X86_GGML_BASE_LIB" ] && X86_LIBS_TO_MERGE="$X86_LIBS_TO_MERGE $X86_GGML_BASE_LIB"
[ -n "$X86_GGML_METAL_LIB" ] && [ -f "$X86_GGML_METAL_LIB" ] && X86_LIBS_TO_MERGE="$X86_LIBS_TO_MERGE $X86_GGML_METAL_LIB"
[ -n "$X86_GGML_CPU_LIB" ] && [ -f "$X86_GGML_CPU_LIB" ] && X86_LIBS_TO_MERGE="$X86_LIBS_TO_MERGE $X86_GGML_CPU_LIB"
[ -n "$X86_GGML_BLAS_LIB" ] && [ -f "$X86_GGML_BLAS_LIB" ] && X86_LIBS_TO_MERGE="$X86_LIBS_TO_MERGE $X86_GGML_BLAS_LIB"
[ -n "$X86_MTMD_LIB" ] && [ -f "$X86_MTMD_LIB" ] && X86_LIBS_TO_MERGE="$X86_LIBS_TO_MERGE $X86_MTMD_LIB"
[ -n "$X86_WHISPER_LIB" ] && [ -f "$X86_WHISPER_LIB" ] && X86_LIBS_TO_MERGE="$X86_LIBS_TO_MERGE $X86_WHISPER_LIB"

echo "Merging arm64 libraries: $ARM64_LIBS_TO_MERGE"
# shellcheck disable=SC2086
libtool -static -o "$MERGED_DIR/arm64/libedge_veda_full.a" $ARM64_LIBS_TO_MERGE 2>/dev/null || {
    echo "libtool merge failed for arm64, using primary library only"
    cp "$ARM64_LIB" "$MERGED_DIR/arm64/libedge_veda_full.a"
}

echo "Merging x86_64 libraries: $X86_LIBS_TO_MERGE"
# shellcheck disable=SC2086
libtool -static -o "$MERGED_DIR/x86_64/libedge_veda_full.a" $X86_LIBS_TO_MERGE 2>/dev/null || {
    echo "libtool merge failed for x86_64, using primary library only"
    cp "$X86_LIB" "$MERGED_DIR/x86_64/libedge_veda_full.a"
}

echo "Merged arm64 library size: $(du -h "$MERGED_DIR/arm64/libedge_veda_full.a" | cut -f1)"
echo "Merged x86_64 library size: $(du -h "$MERGED_DIR/x86_64/libedge_veda_full.a" | cut -f1)"

# ============================================================================
# Create universal (fat) binary via lipo
# ============================================================================
echo ""
echo "=== Creating universal binary ==="

mkdir -p "$MERGED_DIR/universal"
lipo -create \
    "$MERGED_DIR/arm64/libedge_veda_full.a" \
    "$MERGED_DIR/x86_64/libedge_veda_full.a" \
    -output "$MERGED_DIR/universal/libedge_veda_full.a"

echo "Universal library size: $(du -h "$MERGED_DIR/universal/libedge_veda_full.a" | cut -f1)"
echo "Architectures:"
lipo -info "$MERGED_DIR/universal/libedge_veda_full.a"

# ============================================================================
# Verify binary sizes
# ============================================================================
echo ""
echo "=== Verifying binary sizes ==="
UNIVERSAL_SIZE_KB=$(du -k "$MERGED_DIR/universal/libedge_veda_full.a" | cut -f1)
MAX_SIZE_KB=20480  # 20MB per arch warning threshold

if [ "$UNIVERSAL_SIZE_KB" -gt "$MAX_SIZE_KB" ]; then
    echo "WARNING: Universal library (${UNIVERSAL_SIZE_KB}KB) exceeds 20MB"
    echo "Consider enabling LTO or stripping symbols: strip -S libedge_veda_full.a"
fi

echo "Universal: ${UNIVERSAL_SIZE_KB}KB (warning threshold: ${MAX_SIZE_KB}KB)"

# ============================================================================
# Create XCFramework
# ============================================================================
echo ""
echo "=== Creating XCFramework ==="

rm -rf "$OUTPUT_DIR/EdgeVedaCore.xcframework"

xcodebuild -create-xcframework \
    -library "$MERGED_DIR/universal/libedge_veda_full.a" \
    -headers "$CORE_DIR/include" \
    -output "$OUTPUT_DIR/EdgeVedaCore.xcframework"

# ============================================================================
# Verify XCFramework
# ============================================================================
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
    find "$OUTPUT_DIR/EdgeVedaCore.xcframework" -name "*.a" -exec du -h {} \;

    # Verify architectures
    echo ""
    echo "Architecture verification:"
    for lib in $(find "$OUTPUT_DIR/EdgeVedaCore.xcframework" -name "*.a"); do
        echo "  $lib:"
        lipo -info "$lib" 2>/dev/null || echo "    (single architecture)"
    done

    # Verify symbols
    echo ""
    echo "=== Symbol verification ==="
    VERIFICATION_FAILED=false
    for lib in $(find "$OUTPUT_DIR/EdgeVedaCore.xcframework" -name "*.a"); do
        # Check ev_* symbols
        EV_SYMBOLS=$(nm -gU "$lib" 2>/dev/null | grep -c "_ev_" || echo "0")
        echo "$lib: $EV_SYMBOLS ev_* symbols found"

        # Check llama.cpp symbols
        LLAMA_SYMBOLS=$(nm -gU "$lib" 2>/dev/null | grep -c "llama_" || echo "0")
        echo "$lib: $LLAMA_SYMBOLS llama_* symbols found"
        if [ "$LLAMA_SYMBOLS" -lt 10 ]; then
            echo "ERROR: Insufficient llama.cpp symbols (found $LLAMA_SYMBOLS, need >= 10)"
            VERIFICATION_FAILED=true
        fi

        # Check mtmd symbols
        MTMD_SYMBOLS=$(nm -gU "$lib" 2>/dev/null | grep -c "mtmd_" || echo "0")
        echo "$lib: $MTMD_SYMBOLS mtmd_* symbols found"

        # Check whisper symbols
        WHISPER_SYMBOLS=$(nm -gU "$lib" 2>/dev/null | grep -c "whisper_" || echo "0")
        echo "$lib: $WHISPER_SYMBOLS whisper_* symbols found"
        if [ "$WHISPER_SYMBOLS" -lt 5 ]; then
            echo "WARNING: Expected at least 5 whisper_* symbols (found $WHISPER_SYMBOLS)"
        fi
    done

    if [ "$VERIFICATION_FAILED" = true ]; then
        echo ""
        echo "VERIFICATION FAILED: Required symbols not properly linked"
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
