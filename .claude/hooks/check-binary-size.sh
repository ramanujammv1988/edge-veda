#!/bin/bash
# .claude/hooks/check-binary-size.sh
# Monitor binary size after builds to ensure we stay within limits

# Size limits in bytes
IOS_LIMIT=$((15 * 1024 * 1024))       # 15MB for iOS
ANDROID_LIMIT=$((15 * 1024 * 1024))   # 15MB for Android
WASM_LIMIT=$((10 * 1024 * 1024))      # 10MB for WASM
FLUTTER_LIMIT=$((25 * 1024 * 1024))   # 25MB for Flutter plugin

ERRORS=0

check_size() {
    local file=$1
    local limit=$2
    local name=$3

    if [ -f "$file" ]; then
        # Cross-platform file size
        if [[ "$OSTYPE" == "darwin"* ]]; then
            size=$(stat -f%z "$file" 2>/dev/null)
        else
            size=$(stat -c%s "$file" 2>/dev/null)
        fi

        if [ -n "$size" ]; then
            size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc 2>/dev/null || echo "?")
            limit_mb=$(echo "scale=0; $limit / 1024 / 1024" | bc 2>/dev/null || echo "?")

            if [ "$size" -gt "$limit" ]; then
                echo "ERROR: $name exceeds size limit!" >&2
                echo "  Size: ${size_mb}MB (limit: ${limit_mb}MB)" >&2
                ERRORS=$((ERRORS + 1))
            else
                echo "OK: $name - ${size_mb}MB (limit: ${limit_mb}MB)"
            fi
        fi
    fi
}

echo "=== Binary Size Check ==="
echo ""

# Check iOS builds
check_size "build/ios/Release-iphoneos/libedge_veda.a" $IOS_LIMIT "iOS Static Library"
check_size "build/ios/EdgeVeda.xcframework" $IOS_LIMIT "iOS XCFramework"

# Check Android builds
for abi in arm64-v8a armeabi-v7a x86_64; do
    check_size "build/android/$abi/libedge_veda.so" $ANDROID_LIMIT "Android ($abi)"
done

# Check WASM build
check_size "build/wasm/edge_veda.wasm" $WASM_LIMIT "WASM Module"
check_size "build/wasm/edge_veda.js" $((2 * 1024 * 1024)) "WASM JS Glue"

# Check Flutter plugin (if built)
if [ -d "flutter/build" ]; then
    # Find any built artifacts
    find flutter/build -name "*.framework" -o -name "*.aar" 2>/dev/null | while read artifact; do
        check_size "$artifact" $FLUTTER_LIMIT "Flutter: $(basename $artifact)"
    done
fi

echo ""

if [ $ERRORS -gt 0 ]; then
    echo "FAILED: $ERRORS binary size violation(s) found" >&2
    echo "" >&2
    echo "Tips to reduce binary size:" >&2
    echo "  - Enable LTO: -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON" >&2
    echo "  - Strip symbols: strip -x <binary>" >&2
    echo "  - Use -Os optimization level" >&2
    echo "  - Remove unused code with -ffunction-sections -fdata-sections" >&2
    exit 1
fi

echo "All binaries within size limits!"
exit 0
