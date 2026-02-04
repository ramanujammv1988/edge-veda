#!/bin/bash
# EdgeVeda Swift SDK - Validation Script
# Validates the package structure and runs tests

set -e  # Exit on error

echo "EdgeVeda Swift SDK - Validation"
echo "================================"
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track results
CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}✗${NC} $1"
        ((CHECKS_FAILED++))
    fi
}

# 1. Check Swift version
echo "1. Checking Swift version..."
swift --version > /dev/null 2>&1
check "Swift is installed"

SWIFT_VERSION=$(swift --version | head -n1)
echo "   $SWIFT_VERSION"
echo ""

# 2. Validate package structure
echo "2. Validating package structure..."

test -f "Package.swift"
check "Package.swift exists"

test -f "Sources/EdgeVeda/EdgeVeda.swift"
check "EdgeVeda.swift exists"

test -f "Sources/EdgeVeda/Config.swift"
check "Config.swift exists"

test -f "Sources/EdgeVeda/Types.swift"
check "Types.swift exists"

test -f "Sources/EdgeVeda/Internal/FFIBridge.swift"
check "FFIBridge.swift exists"

test -f "Sources/CEdgeVeda/include/edge_veda.h"
check "edge_veda.h exists"

test -f "Tests/EdgeVedaTests/EdgeVedaTests.swift"
check "Tests exist"

echo ""

# 3. Check documentation
echo "3. Checking documentation..."

test -f "README.md"
check "README.md exists"

test -f "API.md"
check "API.md exists"

test -f "INTEGRATION.md"
check "INTEGRATION.md exists"

test -f "STRUCTURE.md"
check "STRUCTURE.md exists"

echo ""

# 4. Validate Package.swift
echo "4. Validating Package.swift..."

swift package dump-package > /dev/null 2>&1
check "Package.swift is valid"

echo ""

# 5. Check for Swift syntax errors
echo "5. Checking Swift syntax..."

swift build --dry-run > /dev/null 2>&1
check "Swift syntax is valid"

echo ""

# 6. Count lines of code
echo "6. Code statistics..."

SWIFT_FILES=$(find Sources -name "*.swift" | wc -l | xargs)
SWIFT_LINES=$(find Sources -name "*.swift" -exec wc -l {} + | tail -1 | awk '{print $1}')
TEST_LINES=$(find Tests -name "*.swift" -exec wc -l {} + | tail -1 | awk '{print $1}')
H_FILES=$(find Sources -name "*.h" | wc -l | xargs)

echo "   Swift source files: $SWIFT_FILES"
echo "   Swift source lines: $SWIFT_LINES"
echo "   Test lines: $TEST_LINES"
echo "   C header files: $H_FILES"
echo ""

# 7. Check examples
echo "7. Checking examples..."

EXAMPLES=$(find Examples -name "*.swift" | wc -l | xargs)
echo "   Example files: $EXAMPLES"

test -f "Examples/SimpleExample.swift"
check "SimpleExample.swift exists"

test -f "Examples/StreamingExample.swift"
check "StreamingExample.swift exists"

test -f "Examples/ConfigExample.swift"
check "ConfigExample.swift exists"

echo ""

# 8. Summary
echo "================================"
echo "Validation Summary"
echo "================================"
echo -e "Passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Failed: ${RED}$CHECKS_FAILED${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Implement the C library (edge_veda.h)"
    echo "  2. Run: swift build"
    echo "  3. Run: swift test"
    echo "  4. Add your GGUF model"
    echo "  5. Try the examples!"
    exit 0
else
    echo -e "${RED}Some checks failed. Please review.${NC}"
    exit 1
fi
