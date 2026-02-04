#!/bin/bash
# .claude/hooks/pre-commit-lint.sh
# Run linters before allowing commits

set -e

echo "Running pre-commit linters..."

# C++ formatting
if command -v clang-format &> /dev/null; then
    echo "Checking C++ formatting..."
    CPP_FILES=$(find core/src core/include -name "*.cpp" -o -name "*.h" 2>/dev/null || true)
    if [ -n "$CPP_FILES" ]; then
        echo "$CPP_FILES" | xargs clang-format --dry-run --Werror 2>/dev/null || {
            echo "ERROR: C++ formatting issues found. Run: clang-format -i <file>"
            exit 1
        }
        echo "  C++ formatting OK"
    fi
fi

# Dart formatting
if [ -d "flutter" ] && command -v dart &> /dev/null; then
    echo "Checking Dart formatting..."
    cd flutter
    dart format --set-exit-if-changed lib/ 2>/dev/null || {
        echo "ERROR: Dart formatting issues found. Run: dart format lib/"
        exit 1
    }
    cd ..
    echo "  Dart formatting OK"
fi

# Swift formatting
if [ -d "swift" ] && command -v swift-format &> /dev/null; then
    echo "Checking Swift formatting..."
    swift-format lint --recursive swift/Sources/ 2>/dev/null || {
        echo "ERROR: Swift formatting issues found. Run: swift-format -i swift/Sources/"
        exit 1
    }
    echo "  Swift formatting OK"
fi

# Kotlin formatting
if [ -d "kotlin" ] && command -v ktlint &> /dev/null; then
    echo "Checking Kotlin formatting..."
    ktlint "kotlin/src/**/*.kt" 2>/dev/null || {
        echo "ERROR: Kotlin formatting issues found. Run: ktlint -F"
        exit 1
    }
    echo "  Kotlin formatting OK"
fi

echo "All linters passed!"
exit 0
