#!/bin/bash
#
# download-xcframework.sh - Download pre-built EdgeVedaCore.xcframework from GitHub Releases
#
# Usage: ./scripts/download-xcframework.sh [version]
# Example: ./scripts/download-xcframework.sh 2.3.1
#
# If no version is specified, reads from flutter/pubspec.yaml.
# The XCFramework is placed at flutter/ios/Frameworks/EdgeVedaCore.xcframework.
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
FRAMEWORK_DIR="$FLUTTER_DIR/ios/Frameworks"
XCFRAMEWORK="$FRAMEWORK_DIR/EdgeVedaCore.xcframework"
PUBSPEC="$FLUTTER_DIR/pubspec.yaml"

REPO="ramanujammv1988/edge-veda"

# Print usage
usage() {
    echo "Usage: $(basename "$0") [version] [--force]"
    echo ""
    echo "Downloads EdgeVedaCore.xcframework from GitHub Releases."
    echo ""
    echo "Arguments:"
    echo "  [version]   Version to download (e.g., 2.3.1). Reads pubspec.yaml if omitted."
    echo "  --force     Re-download even if XCFramework already exists."
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")              # Download version from pubspec.yaml"
    echo "  $(basename "$0") 2.3.1        # Download specific version"
    echo "  $(basename "$0") --force      # Force re-download"
}

# Extract version from pubspec.yaml
get_pubspec_version() {
    if [ ! -f "$PUBSPEC" ]; then
        echo ""
        return
    fi
    grep -E "^version:" "$PUBSPEC" | head -1 | sed 's/version:[[:space:]]*//' | tr -d "'"'"'
}

# Parse arguments
FORCE=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

# Resolve version
if [ -z "$VERSION" ]; then
    VERSION=$(get_pubspec_version)
    if [ -z "$VERSION" ]; then
        echo -e "${RED}ERROR:${NC} Could not determine version."
        echo "  Specify a version: $(basename "$0") 2.3.1"
        echo "  Or ensure flutter/pubspec.yaml exists."
        exit 1
    fi
    echo "Version from pubspec.yaml: $VERSION"
fi

# Check if already present
if [ -d "$XCFRAMEWORK" ] && [ "$FORCE" = false ]; then
    echo -e "${GREEN}[OK]${NC} EdgeVedaCore.xcframework already present at:"
    echo "     $XCFRAMEWORK"
    echo ""
    echo "  Use --force to re-download."
    exit 0
fi

URL="https://github.com/$REPO/releases/download/v$VERSION/EdgeVedaCore.xcframework.zip"

echo "================================================"
echo "EdgeVedaCore.xcframework Downloader"
echo "================================================"
echo ""
echo "  Version:     $VERSION"
echo "  URL:         $URL"
echo "  Destination: $FRAMEWORK_DIR/"
echo ""

# Create output directory
mkdir -p "$FRAMEWORK_DIR"

# Remove existing if forcing
if [ -d "$XCFRAMEWORK" ]; then
    echo "Removing existing XCFramework..."
    rm -rf "$XCFRAMEWORK"
fi

# Download
ZIP_FILE="$FRAMEWORK_DIR/EdgeVedaCore.xcframework.zip"
echo "Downloading..."

if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -L --progress-bar -w "%{http_code}" -o "$ZIP_FILE" "$URL" 2>&1 | tail -1)
    # curl with progress-bar sends progress to stderr, HTTP code to stdout
    HTTP_CODE=$(curl -L -s -w "%{http_code}" -o "$ZIP_FILE" "$URL")
    if [ "$HTTP_CODE" != "200" ]; then
        rm -f "$ZIP_FILE"
        echo ""
        echo -e "${RED}ERROR:${NC} Download failed (HTTP $HTTP_CODE)"
        echo ""
        echo "  The pre-built binary for v$VERSION was not found."
        echo "  Check available releases: https://github.com/$REPO/releases"
        echo ""
        echo "  Alternatively, build from source:"
        echo "    ./scripts/build-ios.sh --clean --release"
        exit 1
    fi
elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$ZIP_FILE" "$URL" || {
        rm -f "$ZIP_FILE"
        echo -e "${RED}ERROR:${NC} Download failed."
        echo "  Check: https://github.com/$REPO/releases"
        exit 1
    }
else
    echo -e "${RED}ERROR:${NC} Neither curl nor wget found."
    exit 1
fi

# Verify it's a zip
if ! file "$ZIP_FILE" | grep -q "Zip"; then
    rm -f "$ZIP_FILE"
    echo -e "${RED}ERROR:${NC} Downloaded file is not a valid zip archive."
    exit 1
fi

# Get file size
ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
echo -e "${GREEN}[OK]${NC} Downloaded ($ZIP_SIZE)"

# Extract
echo "Extracting..."
unzip -q -o "$ZIP_FILE" -d "$FRAMEWORK_DIR"
rm -f "$ZIP_FILE"

# Handle nested directory structure
if [ ! -d "$XCFRAMEWORK" ]; then
    FOUND=$(find "$FRAMEWORK_DIR" -name "EdgeVedaCore.xcframework" -type d -maxdepth 2 | head -1)
    if [ -n "$FOUND" ] && [ "$FOUND" != "$XCFRAMEWORK" ]; then
        mv "$FOUND" "$XCFRAMEWORK"
    else
        echo -e "${RED}ERROR:${NC} XCFramework not found after extraction."
        exit 1
    fi
fi

# Verify structure
if [ ! -f "$XCFRAMEWORK/Info.plist" ]; then
    echo -e "${RED}ERROR:${NC} Invalid XCFramework — missing Info.plist"
    exit 1
fi

# Count slices
SLICE_COUNT=$(find "$XCFRAMEWORK" -name "EdgeVedaCore" -not -name "*.xcframework" -not -name "*.plist" | wc -l | tr -d ' ')

echo ""
echo "================================================"
echo -e "${GREEN}Success${NC}"
echo "================================================"
echo ""
echo "  XCFramework: $XCFRAMEWORK"
echo "  Slices:      $SLICE_COUNT (device arm64 + simulator arm64)"
echo ""
echo "  Run 'flutter build ios' to build your app."
