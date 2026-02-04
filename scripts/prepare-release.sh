#!/bin/bash
#
# prepare-release.sh - Validate version consistency and run pre-release checks
#
# Usage: ./scripts/prepare-release.sh <version>
# Example: ./scripts/prepare-release.sh 1.0.0
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$PROJECT_ROOT/flutter"

# Files to check
PUBSPEC="$FLUTTER_DIR/pubspec.yaml"
PODSPEC="$FLUTTER_DIR/ios/edge_veda.podspec"
CHANGELOG="$FLUTTER_DIR/CHANGELOG.md"

# Print colored status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "ok" ]; then
        echo -e "${GREEN}[OK]${NC} $message"
    elif [ "$status" = "warn" ]; then
        echo -e "${YELLOW}[WARN]${NC} $message"
    else
        echo -e "${RED}[FAIL]${NC} $message"
    fi
}

# Print usage
usage() {
    echo "Usage: $(basename "$0") <version>"
    echo ""
    echo "Validates version consistency across pubspec.yaml, podspec, and CHANGELOG.md,"
    echo "then runs a dry-run publish to check for any issues."
    echo ""
    echo "Arguments:"
    echo "  <version>    Expected version in semver format (e.g., 1.0.0)"
    echo ""
    echo "Options:"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") 1.0.0"
    echo "  $(basename "$0") 1.1.0-beta.1"
    echo ""
    echo "Files checked:"
    echo "  - flutter/pubspec.yaml (version field)"
    echo "  - flutter/ios/edge_veda.podspec (s.version)"
    echo "  - flutter/CHANGELOG.md ([X.Y.Z] entry)"
}

# Validate semver format
validate_semver() {
    local version=$1
    # Match X.Y.Z or X.Y.Z-prerelease or X.Y.Z-prerelease.N
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        echo "Error: Invalid version format '$version'"
        echo "Expected semver format: X.Y.Z (e.g., 1.0.0) or X.Y.Z-prerelease (e.g., 1.0.0-beta.1)"
        exit 1
    fi
}

# Extract version from pubspec.yaml
get_pubspec_version() {
    if [ ! -f "$PUBSPEC" ]; then
        echo "NOT_FOUND"
        return
    fi
    grep -E "^version:" "$PUBSPEC" | head -1 | sed 's/version:[[:space:]]*//' | tr -d "'"'"'
}

# Extract version from podspec
get_podspec_version() {
    if [ ! -f "$PODSPEC" ]; then
        echo "NOT_FOUND"
        return
    fi
    grep "s.version" "$PODSPEC" | head -1 | sed "s/.*=.*'\([^']*\)'.*/\1/"
}

# Check if version exists in CHANGELOG.md
get_changelog_version() {
    local version=$1
    if [ ! -f "$CHANGELOG" ]; then
        echo "NOT_FOUND"
        return
    fi
    # Look for ## [X.Y.Z] pattern
    if grep -q "## \[$version\]" "$CHANGELOG"; then
        echo "$version"
    else
        echo "NOT_FOUND"
    fi
}

# Main validation
main() {
    # Handle help
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        usage
        exit 0
    fi

    # Check argument
    if [ -z "$1" ]; then
        echo "Error: Version argument required"
        echo ""
        usage
        exit 1
    fi

    local expected_version=$1
    local errors=0
    local warnings=0

    echo "================================================"
    echo "Edge Veda Release Validation"
    echo "Expected version: $expected_version"
    echo "================================================"
    echo ""

    # Validate semver format
    validate_semver "$expected_version"

    # Check versions
    echo "Checking version consistency..."
    echo ""

    # pubspec.yaml
    local pubspec_version
    pubspec_version=$(get_pubspec_version)
    if [ "$pubspec_version" = "NOT_FOUND" ]; then
        print_status "fail" "pubspec.yaml: File not found"
        errors=$((errors + 1))
    elif [ "$pubspec_version" = "$expected_version" ]; then
        print_status "ok" "pubspec.yaml: $pubspec_version"
    else
        print_status "fail" "pubspec.yaml: $pubspec_version (expected $expected_version)"
        errors=$((errors + 1))
    fi

    # podspec
    local podspec_version
    podspec_version=$(get_podspec_version)
    if [ "$podspec_version" = "NOT_FOUND" ]; then
        print_status "fail" "podspec: File not found"
        errors=$((errors + 1))
    elif [ "$podspec_version" = "$expected_version" ]; then
        print_status "ok" "podspec: $podspec_version"
    else
        print_status "fail" "podspec: $podspec_version (expected $expected_version)"
        errors=$((errors + 1))
    fi

    # CHANGELOG.md
    local changelog_version
    changelog_version=$(get_changelog_version "$expected_version")
    if [ "$changelog_version" = "NOT_FOUND" ]; then
        print_status "fail" "CHANGELOG.md: Entry [$expected_version] not found"
        errors=$((errors + 1))
    else
        print_status "ok" "CHANGELOG.md: [$changelog_version] entry found"
    fi

    echo ""

    # Summary for versions
    if [ $errors -eq 0 ]; then
        echo -e "Versions: ${GREEN}OK${NC} (all files match $expected_version)"
    else
        echo -e "Versions: ${RED}FAILED${NC} ($errors mismatches)"
    fi

    echo ""

    # Run dry-run publish
    echo "Running dry-run publish..."
    echo ""

    cd "$FLUTTER_DIR"

    # Run flutter pub get first
    if command -v flutter &> /dev/null; then
        flutter pub get --quiet 2>/dev/null || true
    fi

    # Run dart pub publish --dry-run and capture output
    local dryrun_output
    local dryrun_exit_code=0
    if command -v dart &> /dev/null; then
        dryrun_output=$(dart pub publish --dry-run 2>&1) || dryrun_exit_code=$?
    else
        dryrun_output="dart command not found - skipping dry-run"
        dryrun_exit_code=127
    fi

    # Parse dry-run results
    local package_size="unknown"
    local has_errors=false

    # Extract package size if available
    if echo "$dryrun_output" | grep -q "Package has"; then
        # Check for issues
        local issue_count
        issue_count=$(echo "$dryrun_output" | grep -oE "Package has [0-9]+ issue" | grep -oE "[0-9]+" || echo "0")
        if [ "$issue_count" != "0" ]; then
            warnings=$((warnings + 1))
            print_status "warn" "Dry-run found $issue_count issue(s)"
        else
            print_status "ok" "Dry-run passed"
        fi
    elif [ $dryrun_exit_code -eq 127 ]; then
        print_status "warn" "Dart not found - dry-run skipped"
        warnings=$((warnings + 1))
    elif [ $dryrun_exit_code -ne 0 ]; then
        print_status "fail" "Dry-run failed (exit code: $dryrun_exit_code)"
        errors=$((errors + 1))
        has_errors=true
    else
        print_status "ok" "Dry-run passed"
    fi

    # Check for size-related warnings
    if echo "$dryrun_output" | grep -qi "size"; then
        local size_line
        size_line=$(echo "$dryrun_output" | grep -i "size" | head -1)
        echo "  Size info: $size_line"
    fi

    # Check for validation errors
    if echo "$dryrun_output" | grep -qi "error"; then
        echo ""
        echo "Dry-run errors:"
        echo "$dryrun_output" | grep -i "error" | head -5 | while read -r line; do
            echo "  $line"
        done
    fi

    echo ""

    # Calculate approximate package size (excluding xcframework)
    local approx_size_kb
    approx_size_kb=$(find "$FLUTTER_DIR" -type f \
        -not -path "*/.git/*" \
        -not -path "*/Frameworks/*" \
        -not -path "*/build/*" \
        -not -path "*/.dart_tool/*" \
        -not -name "*.xcframework*" \
        -exec du -k {} + 2>/dev/null | awk '{total += $1} END {print total}')
    local approx_size_mb
    approx_size_mb=$(echo "scale=2; ${approx_size_kb:-0} / 1024" | bc 2>/dev/null || echo "unknown")

    if [ "$approx_size_mb" != "unknown" ]; then
        echo "Package size: ~${approx_size_mb}MB (estimated, excluding XCFramework)"
        echo "  Limit: 100MB"
        if (( $(echo "$approx_size_mb > 100" | bc -l 2>/dev/null || echo 0) )); then
            print_status "fail" "Package exceeds 100MB limit"
            errors=$((errors + 1))
        elif (( $(echo "$approx_size_mb > 50" | bc -l 2>/dev/null || echo 0) )); then
            print_status "warn" "Package size > 50MB (approaching limit)"
            warnings=$((warnings + 1))
        else
            print_status "ok" "Package size within limits"
        fi
    fi

    echo ""
    echo "================================================"
    echo "Summary"
    echo "================================================"
    echo ""

    # Final summary
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}Ready to release v$expected_version${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Create git tag: git tag v$expected_version"
        echo "  2. Push tag: git push origin v$expected_version"
        echo "  3. Build XCFramework: ./scripts/build-ios.sh --clean --release"
        echo "  4. Upload XCFramework to GitHub Releases"
        echo "  5. Publish to pub.dev: cd flutter && dart pub publish"
        exit 0
    else
        echo -e "${RED}Release blocked: $errors error(s), $warnings warning(s)${NC}"
        echo ""
        echo "Fix the issues above before releasing."
        exit 1
    fi
}

main "$@"
