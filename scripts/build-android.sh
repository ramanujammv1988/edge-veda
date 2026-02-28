#!/bin/bash
set -e

# Build Android shared library for Edge Veda SDK
# Usage: ./scripts/build-android.sh [--clean] [--release]
#
# This script builds libedge_veda.so for Android arm64-v8a using the Android NDK.
# Follows the same conventions as build-ios.sh and build-macos.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$PROJECT_ROOT/core"
BUILD_DIR="$PROJECT_ROOT/build"
NDK_VERSION="27.2.12479018"

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

echo "=== Edge Veda Android Build ==="
echo "Build type: $BUILD_TYPE"
echo "Project root: $PROJECT_ROOT"

# Check for required tools
check_tools() {
    local missing=0

    if ! command -v cmake &> /dev/null; then
        echo "ERROR: cmake not found. Install with: brew install cmake (macOS) or apt install cmake (Linux)"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

check_tools

# Locate Android NDK
if [ -z "$ANDROID_NDK_HOME" ]; then
    if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME/ndk/$NDK_VERSION" ]; then
        ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$NDK_VERSION"
    else
        echo "ERROR: ANDROID_NDK_HOME is not set, and NDK $NDK_VERSION not found in $ANDROID_HOME."
        echo "Please install NDK version $NDK_VERSION or set ANDROID_NDK_HOME manually."
        echo ""
        echo "To install NDK $NDK_VERSION:"
        echo "  sdkmanager --install 'ndk;$NDK_VERSION'"
        exit 1
    fi
fi

echo "Using Android NDK at: $ANDROID_NDK_HOME"

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning previous builds..."
    rm -rf "$BUILD_DIR/android"
fi

# Initialize submodules if needed
if [ ! -f "$CORE_DIR/third_party/llama.cpp/CMakeLists.txt" ] || \
   [ ! -f "$CORE_DIR/third_party/whisper.cpp/CMakeLists.txt" ] || \
   [ ! -f "$CORE_DIR/third_party/stable-diffusion.cpp/CMakeLists.txt" ]; then
    echo "Initializing git submodules..."
    cd "$PROJECT_ROOT"
    git submodule update --init --recursive
fi

# Define target ABIs (arm64-v8a only for initial release)
ABIS=("arm64-v8a")
# Future: add armeabi-v7a, x86_64 as needed

# Build for each ABI
for ABI in "${ABIS[@]}"; do
    echo ""
    echo "=== Building for ABI: $ABI ==="

    ABI_BUILD_DIR="$BUILD_DIR/android/$ABI"
    mkdir -p "$ABI_BUILD_DIR"

    # Determine CPU count for parallel builds
    if command -v nproc &> /dev/null; then
        NCPU=$(nproc)
    elif command -v sysctl &> /dev/null; then
        NCPU=$(sysctl -n hw.ncpu)
    else
        NCPU=4
    fi

    # Run CMake configure
    cmake -B "$ABI_BUILD_DIR" \
        -S "$CORE_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM=android-24 \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
        -DEDGE_VEDA_BUILD_SHARED=ON \
        -DEDGE_VEDA_BUILD_STATIC=OFF \
        -DEDGE_VEDA_ENABLE_VULKAN=OFF \
        -DEDGE_VEDA_ENABLE_CPU=ON \
        -DGGML_OPENMP=OFF \
        -DGGML_LLAMAFILE=OFF

    # Run CMake build
    cmake --build "$ABI_BUILD_DIR" --config $BUILD_TYPE --parallel "$NCPU"

    # Find the built shared library
    echo ""
    echo "=== Locating shared library for $ABI ==="

    SO_FILE=""
    if [ -f "$ABI_BUILD_DIR/libedge_veda.so" ]; then
        SO_FILE="$ABI_BUILD_DIR/libedge_veda.so"
    elif [ -f "$ABI_BUILD_DIR/$BUILD_TYPE/libedge_veda.so" ]; then
        SO_FILE="$ABI_BUILD_DIR/$BUILD_TYPE/libedge_veda.so"
    else
        SO_FILE=$(find "$ABI_BUILD_DIR" -name "libedge_veda.so" 2>/dev/null | head -1)
    fi

    if [ -z "$SO_FILE" ] || [ ! -f "$SO_FILE" ]; then
        echo "ERROR: Shared library not found for $ABI"
        echo "Searching for edge_veda files:"
        find "$ABI_BUILD_DIR" -name "*edge_veda*" -ls
        exit 1
    fi

    echo "Shared library: $SO_FILE"
    echo "Library size: $(du -h "$SO_FILE" | cut -f1)"

    # Symbol verification
    echo ""
    echo "=== Symbol verification for $ABI ==="
    VERIFICATION_FAILED=false

    # Check ev_* symbols (C API from edge_veda.h)
    EV_SYMBOLS=$(nm -D "$SO_FILE" 2>/dev/null | grep -c " T ev_" || echo "0")
    echo "ev_* symbols: $EV_SYMBOLS"
    if [ "$EV_SYMBOLS" -lt 20 ]; then
        echo "ERROR: Insufficient ev_* symbols (found $EV_SYMBOLS, need >= 20)"
        VERIFICATION_FAILED=true
    fi

    # Check JNI symbols (bridge_jni.cpp entry points)
    JNI_SYMBOLS=$(nm -D "$SO_FILE" 2>/dev/null | grep -c "Java_com_edgeveda" || echo "0")
    echo "JNI symbols: $JNI_SYMBOLS"
    if [ "$JNI_SYMBOLS" -lt 5 ]; then
        echo "WARNING: Expected at least 5 JNI symbols (found $JNI_SYMBOLS)"
    fi

    # Check llama.cpp symbols
    LLAMA_SYMBOLS=$(nm -D "$SO_FILE" 2>/dev/null | grep -c "llama_" || echo "0")
    echo "llama.cpp symbols: $LLAMA_SYMBOLS"
    if [ "$LLAMA_SYMBOLS" -lt 10 ]; then
        echo "WARNING: Expected at least 10 llama.cpp symbols (found $LLAMA_SYMBOLS)"
    fi

    # 16KB page alignment verification (Android 15+ requirement)
    echo ""
    echo "=== 16KB page alignment check ==="
    if readelf -l "$SO_FILE" 2>/dev/null | grep -q "LOAD.*0x4000"; then
        echo "16KB alignment: OK (0x4000 detected)"
    else
        # Check for any alignment >= 0x4000
        MAX_ALIGN=$(readelf -l "$SO_FILE" 2>/dev/null | grep "LOAD" | awk '{print $NF}' | sort -u | tail -1)
        if [ -n "$MAX_ALIGN" ]; then
            echo "Max alignment detected: $MAX_ALIGN"
            # Convert hex to decimal and compare
            ALIGN_DEC=$((16#${MAX_ALIGN#0x}))
            if [ "$ALIGN_DEC" -ge 16384 ]; then
                echo "16KB alignment: OK (>= 16384 bytes)"
            else
                echo "WARNING: 16KB alignment not confirmed (found $MAX_ALIGN, need >= 0x4000)"
            fi
        else
            echo "WARNING: Could not verify page alignment"
        fi
    fi

    # Size verification
    echo ""
    echo "=== Binary size check ==="
    SO_SIZE_KB=$(du -k "$SO_FILE" | cut -f1)
    MAX_SIZE_KB=102400  # 100MB warning threshold
    if [ "$SO_SIZE_KB" -gt "$MAX_SIZE_KB" ]; then
        echo "WARNING: Shared library (${SO_SIZE_KB}KB) exceeds 100MB"
    fi
    echo "Library size: ${SO_SIZE_KB}KB (limit: ${MAX_SIZE_KB}KB)"

    if [ "$VERIFICATION_FAILED" = true ]; then
        echo ""
        echo "VERIFICATION FAILED: Required symbols missing"
        exit 1
    fi
done

echo ""
echo "=== Build Complete ==="
echo "Shared libraries ready at:"
for ABI in "${ABIS[@]}"; do
    ABI_BUILD_DIR="$BUILD_DIR/android/$ABI"
    SO_FILE=$(find "$ABI_BUILD_DIR" -name "libedge_veda.so" 2>/dev/null | head -1)
    if [ -n "$SO_FILE" ]; then
        echo "  $ABI: $SO_FILE"
    fi
done

echo ""
echo "=== Done ==="
