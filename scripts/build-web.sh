#!/bin/bash
# Build Edge Veda C++ core to WebAssembly using Emscripten
#
# Prerequisites:
#   - Emscripten SDK installed and activated (source emsdk_env.sh)
#   - cmake 3.22+
#
# Usage:
#   ./scripts/build-web.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$ROOT_DIR/core"
BUILD_DIR="$ROOT_DIR/build/web"
OUTPUT_DIR="$ROOT_DIR/flutter/web/wasm"

echo "=== Edge Veda Web (WASM) Build ==="
echo "Core: $CORE_DIR"
echo "Output: $OUTPUT_DIR"

# Check for emscripten
if ! command -v emcmake &> /dev/null; then
    echo "ERROR: Emscripten not found. Install emsdk and run 'source emsdk_env.sh'"
    exit 1
fi

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# CMake configure with Emscripten
cd "$BUILD_DIR"
emcmake cmake "$CORE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_WASM_SIMD=ON \
    -DLLAMA_NATIVE=OFF \
    -DLLAMA_METAL=OFF \
    -DLLAMA_VULKAN=OFF \
    -DLLAMA_CUDA=OFF \
    -DCMAKE_C_FLAGS="-pthread -msimd128" \
    -DCMAKE_CXX_FLAGS="-pthread -msimd128"

# Build
emmake make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) edge_veda

# Link to WASM + JS glue
emcc \
    -O3 \
    -s WASM=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s MAXIMUM_MEMORY=2147483648 \
    -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","UTF8ToString","stringToUTF8","_malloc","_free"]' \
    -s EXPORTED_FUNCTIONS='["_ev_init","_ev_free","_ev_generate","_ev_generate_stream","_ev_stream_next","_ev_stream_has_next","_ev_stream_cancel","_ev_stream_free","_ev_free_string","_ev_get_memory_usage","_ev_embed","_ev_free_embeddings","_ev_version","_ev_config_default","_ev_generation_params_default","_ev_error_string","_ev_stream_get_token_info","_ev_is_valid","_ev_reset"]' \
    -s PTHREAD_POOL_SIZE=4 \
    -s MODULARIZE=1 \
    -s EXPORT_NAME="EdgeVedaWasm" \
    -s ENVIRONMENT="web,worker" \
    --pre-js "$SCRIPT_DIR/web-pre.js" \
    -o "$OUTPUT_DIR/edge_veda.js" \
    libedge_veda.a

echo ""
echo "=== Build complete ==="
echo "  JS:   $OUTPUT_DIR/edge_veda.js"
echo "  WASM: $OUTPUT_DIR/edge_veda.wasm"
echo ""
echo "Include in your Flutter web app's index.html:"
echo "  <script src=\"wasm/edge_veda.js\"></script>"
