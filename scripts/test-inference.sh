#!/bin/bash
set -e

# Test Edge Veda inference on macOS (not iOS - needs device)
# Usage: ./scripts/test-inference.sh <model.gguf> [prompt]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$PROJECT_ROOT/core"
BUILD_DIR="$PROJECT_ROOT/build/macos-test"

echo "=== Edge Veda Inference Test ==="

# Check for model path
if [ -z "$1" ]; then
    echo "Usage: $0 <model.gguf> [prompt]"
    echo ""
    echo "Example:"
    echo "  $0 ~/models/llama-3.2-1b-q4_k_m.gguf"
    echo "  $0 ~/models/llama-3.2-1b-q4_k_m.gguf 'What is 2+2?'"
    echo ""
    echo "You can download a test model from:"
    echo "  https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF"
    exit 1
fi

MODEL_PATH="$1"
PROMPT="${2:-Hello, I am a helpful AI assistant.}"

# Verify model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: Model file not found: $MODEL_PATH"
    exit 1
fi

# Initialize submodules if needed
if [ ! -f "$CORE_DIR/third_party/llama.cpp/CMakeLists.txt" ]; then
    echo "Initializing git submodules..."
    cd "$PROJECT_ROOT"
    git submodule update --init --recursive
fi

# Build for macOS (native, for testing)
echo ""
echo "Building test executable for macOS..."
mkdir -p "$BUILD_DIR"

cmake -B "$BUILD_DIR" \
    -S "$CORE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DEDGE_VEDA_BUILD_SHARED=OFF \
    -DEDGE_VEDA_BUILD_STATIC=ON \
    -DEDGE_VEDA_BUILD_TESTS=ON \
    -DEDGE_VEDA_ENABLE_METAL=ON

cmake --build "$BUILD_DIR" --config Release -j$(sysctl -n hw.ncpu)

# Find test executable
TEST_EXE="$BUILD_DIR/tests/test_inference"
if [ ! -f "$TEST_EXE" ]; then
    TEST_EXE=$(find "$BUILD_DIR" -name "test_inference" -type f | head -1)
fi

if [ ! -f "$TEST_EXE" ]; then
    echo "ERROR: Test executable not found"
    find "$BUILD_DIR" -name "test_*" -ls
    exit 1
fi

echo ""
echo "Running test..."
echo "Model: $MODEL_PATH"
echo "Prompt: $PROMPT"
echo ""

# Run the test
"$TEST_EXE" "$MODEL_PATH" "$PROMPT"
