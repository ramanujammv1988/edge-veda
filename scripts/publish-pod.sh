#!/bin/bash
#
# publish-pod.sh - Package and publish EdgeVedaCore to CocoaPods trunk
#
# Usage: ./scripts/publish-pod.sh <version> [--dry-run] [--skip-lint]
#
# Steps:
#   1. Validate version matches EdgeVedaCore.podspec, edge_veda.podspec, pubspec.yaml
#   2. Check XCFramework exists (build first if needed)
#   3. Zip the XCFramework with correct structure
#   4. Create GitHub Release with the zip attached
#   5. Validate the podspec (pod spec lint)
#   6. Push EdgeVedaCore to CocoaPods trunk
#
# Prerequisites:
#   - gh CLI installed and authenticated
#   - pod trunk register (CocoaPods trunk login)
#   - XCFramework built: ./scripts/build-ios.sh --clean --release
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PODSPEC="$PROJECT_ROOT/EdgeVedaCore.podspec"
FLUTTER_PODSPEC="$PROJECT_ROOT/flutter/ios/edge_veda.podspec"
PUBSPEC="$PROJECT_ROOT/flutter/pubspec.yaml"
XCFRAMEWORK="$PROJECT_ROOT/flutter/ios/Frameworks/EdgeVedaCore.xcframework"
ZIP_NAME="EdgeVedaCore.xcframework.zip"

DRY_RUN=false
SKIP_LINT=false

usage() {
    echo "Usage: $(basename "$0") <version> [--dry-run] [--skip-lint]"
    echo ""
    echo "Package and publish EdgeVedaCore to CocoaPods trunk."
    echo ""
    echo "Arguments:"
    echo "  <version>      Version to publish (e.g., 2.3.1)"
    echo ""
    echo "Options:"
    echo "  --dry-run      Validate everything but don't publish"
    echo "  --skip-lint    Skip pod spec lint (for re-runs)"
    echo "  --help, -h     Show this help"
    echo ""
    echo "Prerequisites:"
    echo "  1. Build XCFramework:  ./scripts/build-ios.sh --clean --release"
    echo "  2. Install gh CLI:     brew install gh"
    echo "  3. Login to trunk:     pod trunk register you@example.com 'Your Name'"
    echo ""
    echo "Example:"
    echo "  ./scripts/publish-pod.sh 2.3.1"
    echo "  ./scripts/publish-pod.sh 2.3.1 --dry-run"
}

step() { echo -e "\n${CYAN}[$1/6]${NC} $2"; }
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }

# Parse arguments
VERSION=""
for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY_RUN=true ;;
        --skip-lint) SKIP_LINT=true ;;
        --help|-h)   usage; exit 0 ;;
        *)           VERSION="$arg" ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Error: Version argument required."
    echo ""
    usage
    exit 1
fi

echo "================================================"
echo "EdgeVedaCore Pod Publisher"
echo "Version: $VERSION"
$DRY_RUN && echo "Mode: DRY RUN (no actual publishing)"
echo "================================================"

ERRORS=0

# ── Step 1: Validate versions ──────────────────────────────────────────

step 1 "Validating version consistency..."

PODSPEC_VER=$(grep "s.version" "$PODSPEC" | head -1 | sed "s/.*'\([^']*\)'.*/\1/")
FLUTTER_VER=$(grep "s.version" "$FLUTTER_PODSPEC" | head -1 | sed "s/.*'\([^']*\)'.*/\1/")
PUBSPEC_VER=$(grep "^version:" "$PUBSPEC" | head -1 | sed 's/version:[[:space:]]*//' | tr -d "'")

if [ "$PODSPEC_VER" = "$VERSION" ]; then
    ok "EdgeVedaCore.podspec: $PODSPEC_VER"
else
    fail "EdgeVedaCore.podspec: $PODSPEC_VER (expected $VERSION)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$FLUTTER_VER" = "$VERSION" ]; then
    ok "edge_veda.podspec: $FLUTTER_VER"
else
    fail "edge_veda.podspec: $FLUTTER_VER (expected $VERSION)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$PUBSPEC_VER" = "$VERSION" ]; then
    ok "pubspec.yaml: $PUBSPEC_VER"
else
    fail "pubspec.yaml: $PUBSPEC_VER (expected $VERSION)"
    ERRORS=$((ERRORS + 1))
fi

# ── Step 2: Check XCFramework exists ───────────────────────────────────

step 2 "Checking XCFramework..."

if [ -d "$XCFRAMEWORK" ]; then
    SIZE=$(du -sh "$XCFRAMEWORK" | cut -f1)
    ok "XCFramework found ($SIZE)"
else
    fail "XCFramework not found at: $XCFRAMEWORK"
    echo ""
    echo "  Build it first:"
    echo "    ./scripts/build-ios.sh --clean --release"
    echo ""
    exit 1
fi

# ── Step 3: Create zip ─────────────────────────────────────────────────

step 3 "Creating zip archive..."

TMPZIP="/tmp/$ZIP_NAME"
rm -f "$TMPZIP"

# Zip must contain EdgeVedaCore.xcframework/ at root level
# (CocoaPods extracts zip and looks for vendored_frameworks relative to root)
# Include LICENSE for CocoaPods validation
TMPDIR_ZIP=$(mktemp -d)
cp -R "$PROJECT_ROOT/flutter/ios/Frameworks/EdgeVedaCore.xcframework" "$TMPDIR_ZIP/"
cp "$PROJECT_ROOT/LICENSE" "$TMPDIR_ZIP/"
cd "$TMPDIR_ZIP"
zip -r -q "$TMPZIP" EdgeVedaCore.xcframework/ LICENSE
cd "$PROJECT_ROOT"
rm -rf "$TMPDIR_ZIP"

ZIP_SIZE=$(du -sh "$TMPZIP" | cut -f1)
ok "Created $TMPZIP ($ZIP_SIZE)"

# Cleanup on exit
cleanup() { rm -f "$TMPZIP"; rm -rf "$TMPDIR_ZIP" 2>/dev/null; }
trap cleanup EXIT

# ── Step 4: GitHub Release ─────────────────────────────────────────────

step 4 "Creating GitHub Release..."

if ! command -v gh &>/dev/null; then
    fail "gh CLI not found. Install: brew install gh"
    ERRORS=$((ERRORS + 1))
else
    if $DRY_RUN; then
        warn "DRY RUN: Would create release v$VERSION with $ZIP_NAME"
    else
        # Check if release already exists
        if gh release view "v$VERSION" &>/dev/null 2>&1; then
            echo "  Release v$VERSION exists — uploading asset..."
            gh release upload "v$VERSION" "$TMPZIP" --clobber
            ok "Uploaded $ZIP_NAME to existing release v$VERSION"
        else
            gh release create "v$VERSION" "$TMPZIP" \
                --title "v$VERSION" \
                --notes "EdgeVedaCore XCFramework for iOS (device arm64 + simulator arm64)"
            ok "Created release v$VERSION with $ZIP_NAME"
        fi
    fi
fi

# ── Step 5: Pod spec lint ──────────────────────────────────────────────

step 5 "Validating podspec..."

if $SKIP_LINT; then
    warn "Skipping lint (--skip-lint)"
else
    if $DRY_RUN; then
        warn "DRY RUN: Would run pod spec lint EdgeVedaCore.podspec"
    else
        echo "  Running pod spec lint (this downloads the zip to verify)..."
        if pod spec lint "$PODSPEC" --allow-warnings --skip-import-validation 2>&1; then
            ok "Pod spec lint passed"
        else
            fail "Pod spec lint failed"
            echo ""
            echo "  If the zip was just uploaded, it may take a minute for GitHub"
            echo "  to make it available. Try again, or use --skip-lint."
            ERRORS=$((ERRORS + 1))
        fi
    fi
fi

# ── Step 6: Push to trunk ─────────────────────────────────────────────

step 6 "Publishing to CocoaPods trunk..."

if $DRY_RUN; then
    warn "DRY RUN: Would run pod trunk push EdgeVedaCore.podspec"
else
    if [ $ERRORS -gt 0 ]; then
        fail "Skipping trunk push due to $ERRORS error(s) above"
    else
        echo "  Running pod trunk push..."
        if pod trunk push "$PODSPEC" --allow-warnings --skip-import-validation 2>&1; then
            ok "EdgeVedaCore $VERSION published to CocoaPods trunk!"
        else
            fail "Pod trunk push failed"
            echo ""
            echo "  Make sure you're registered: pod trunk register you@example.com 'Your Name'"
            echo "  Then check your email to verify."
            ERRORS=$((ERRORS + 1))
        fi
    fi
fi

# ── Summary ────────────────────────────────────────────────────────────

echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

if [ $ERRORS -eq 0 ]; then
    if $DRY_RUN; then
        echo -e "${GREEN}Dry run passed.${NC} Ready to publish."
        echo ""
        echo "Run without --dry-run to publish:"
        echo "  ./scripts/publish-pod.sh $VERSION"
    else
        echo -e "${GREEN}EdgeVedaCore $VERSION published!${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Publish to pub.dev: cd flutter && dart pub publish"
        echo "  2. Verify consumer flow: flutter create test_app && cd test_app"
        echo "     flutter pub add edge_veda && flutter build ios"
    fi
else
    echo -e "${RED}Publishing failed: $ERRORS error(s)${NC}"
    echo ""
    echo "Fix the issues above and try again."
    exit 1
fi
