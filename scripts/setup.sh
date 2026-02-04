#!/bin/bash
#
# Edge Veda SDK - Developer Setup Script
# This script checks dependencies, initializes submodules, and performs initial builds
#

set -e  # Exit on error

# Colors for output
COLOR_RESET='\033[0m'
COLOR_BOLD='\033[1m'
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_RED='\033[31m'
COLOR_BLUE='\033[34m'

# Helper functions
print_header() {
    echo -e "${COLOR_BOLD}${COLOR_BLUE}===> $1${COLOR_RESET}"
}

print_success() {
    echo -e "${COLOR_BOLD}${COLOR_GREEN}✓ $1${COLOR_RESET}"
}

print_warning() {
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}⚠ $1${COLOR_RESET}"
}

print_error() {
    echo -e "${COLOR_BOLD}${COLOR_RED}✗ $1${COLOR_RESET}"
}

print_info() {
    echo -e "${COLOR_BLUE}  $1${COLOR_RESET}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Version comparison
version_ge() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    else
        OS="unknown"
    fi
}

# Banner
print_banner() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_BLUE}"
    echo "  ███████╗██████╗  ██████╗ ███████╗    ██╗   ██╗███████╗██████╗  █████╗ "
    echo "  ██╔════╝██╔══██╗██╔════╝ ██╔════╝    ██║   ██║██╔════╝██╔══██╗██╔══██╗"
    echo "  █████╗  ██║  ██║██║  ███╗█████╗      ██║   ██║█████╗  ██║  ██║███████║"
    echo "  ██╔══╝  ██║  ██║██║   ██║██╔══╝      ╚██╗ ██╔╝██╔══╝  ██║  ██║██╔══██║"
    echo "  ███████╗██████╔╝╚██████╔╝███████╗     ╚████╔╝ ███████╗██████╔╝██║  ██║"
    echo "  ╚══════╝╚═════╝  ╚═════╝ ╚══════╝      ╚═══╝  ╚══════╝╚═════╝ ╚═╝  ╚═╝"
    echo -e "${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  Knowledge at the Edge - Developer Setup${COLOR_RESET}"
    echo ""
}

# Check CMake
check_cmake() {
    print_header "Checking CMake"

    if ! command_exists cmake; then
        print_error "CMake not found"
        print_info "Please install CMake 3.21 or later"

        if [[ "$OS" == "macos" ]]; then
            print_info "Run: brew install cmake"
        elif [[ "$OS" == "linux" ]]; then
            print_info "Run: sudo apt-get install cmake"
        fi
        return 1
    fi

    CMAKE_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
    if version_ge "$CMAKE_VERSION" "3.21.0"; then
        print_success "CMake $CMAKE_VERSION found"
    else
        print_warning "CMake $CMAKE_VERSION found, but 3.21+ is recommended"
    fi
}

# Check Ninja
check_ninja() {
    print_header "Checking Ninja"

    if ! command_exists ninja; then
        print_warning "Ninja build system not found (optional but recommended)"

        if [[ "$OS" == "macos" ]]; then
            print_info "Run: brew install ninja"
        elif [[ "$OS" == "linux" ]]; then
            print_info "Run: sudo apt-get install ninja-build"
        fi
    else
        NINJA_VERSION=$(ninja --version)
        print_success "Ninja $NINJA_VERSION found"
    fi
}

# Check Flutter
check_flutter() {
    print_header "Checking Flutter"

    if ! command_exists flutter; then
        print_error "Flutter not found"
        print_info "Please install Flutter 3.10 or later"
        print_info "Visit: https://flutter.dev/docs/get-started/install"
        return 1
    fi

    FLUTTER_VERSION=$(flutter --version | head -n1 | awk '{print $2}')
    if version_ge "$FLUTTER_VERSION" "3.10.0"; then
        print_success "Flutter $FLUTTER_VERSION found"
    else
        print_warning "Flutter $FLUTTER_VERSION found, but 3.10+ is recommended"
    fi

    # Check Flutter doctor
    print_info "Running flutter doctor..."
    flutter doctor -v
}

# Check Xcode (macOS only)
check_xcode() {
    if [[ "$OS" != "macos" ]]; then
        return 0
    fi

    print_header "Checking Xcode"

    if ! command_exists xcodebuild; then
        print_error "Xcode not found"
        print_info "Please install Xcode from the App Store"
        return 1
    fi

    XCODE_VERSION=$(xcodebuild -version | head -n1 | awk '{print $2}')
    print_success "Xcode $XCODE_VERSION found"

    # Check for command line tools
    if ! xcode-select -p >/dev/null 2>&1; then
        print_warning "Xcode command line tools not configured"
        print_info "Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    else
        print_success "Xcode command line tools configured"
    fi
}

# Check Android NDK
check_android_ndk() {
    print_header "Checking Android NDK"

    if [ -z "$ANDROID_NDK_HOME" ] && [ -z "$ANDROID_NDK" ]; then
        print_warning "Android NDK not found (required for Android builds)"
        print_info "Set ANDROID_NDK_HOME environment variable"
        print_info "Download: https://developer.android.com/ndk/downloads"
        return 1
    fi

    NDK_PATH="${ANDROID_NDK_HOME:-$ANDROID_NDK}"
    if [ -d "$NDK_PATH" ]; then
        # Try to get NDK version
        if [ -f "$NDK_PATH/source.properties" ]; then
            NDK_VERSION=$(grep "Pkg.Revision" "$NDK_PATH/source.properties" | cut -d= -f2 | tr -d ' ')
            print_success "Android NDK $NDK_VERSION found at $NDK_PATH"
        else
            print_success "Android NDK found at $NDK_PATH"
        fi
    else
        print_error "Android NDK path exists but directory not found: $NDK_PATH"
        return 1
    fi
}

# Check Node.js (for React Native)
check_nodejs() {
    print_header "Checking Node.js"

    if ! command_exists node; then
        print_warning "Node.js not found (required for React Native)"
        print_info "Install from: https://nodejs.org/"
        return 1
    fi

    NODE_VERSION=$(node --version | sed 's/v//')
    if version_ge "$NODE_VERSION" "18.0.0"; then
        print_success "Node.js $NODE_VERSION found"
    else
        print_warning "Node.js $NODE_VERSION found, but 18+ is recommended"
    fi
}

# Check Swift (macOS only)
check_swift() {
    if [[ "$OS" != "macos" ]]; then
        return 0
    fi

    print_header "Checking Swift"

    if ! command_exists swift; then
        print_error "Swift not found"
        return 1
    fi

    SWIFT_VERSION=$(swift --version | head -n1 | awk '{print $4}')
    print_success "Swift $SWIFT_VERSION found"
}

# Check Python (optional, for scripts)
check_python() {
    print_header "Checking Python"

    if ! command_exists python3; then
        print_warning "Python 3 not found (optional)"
    else
        PYTHON_VERSION=$(python3 --version | awk '{print $2}')
        print_success "Python $PYTHON_VERSION found"
    fi
}

# Check ccache (optional, for faster builds)
check_ccache() {
    print_header "Checking ccache"

    if ! command_exists ccache; then
        print_warning "ccache not found (optional, but speeds up rebuilds)"

        if [[ "$OS" == "macos" ]]; then
            print_info "Run: brew install ccache"
        elif [[ "$OS" == "linux" ]]; then
            print_info "Run: sudo apt-get install ccache"
        fi
    else
        CCACHE_VERSION=$(ccache --version | head -n1 | awk '{print $3}')
        print_success "ccache $CCACHE_VERSION found"
    fi
}

# Clone/update submodules
setup_submodules() {
    print_header "Setting up Git submodules"

    if [ ! -d ".git" ]; then
        print_warning "Not a git repository, skipping submodules"
        return 0
    fi

    if [ -f ".gitmodules" ]; then
        print_info "Initializing submodules..."
        git submodule update --init --recursive
        print_success "Submodules initialized"
    else
        print_info "No submodules configured"
    fi
}

# Install Flutter dependencies
setup_flutter() {
    print_header "Setting up Flutter dependencies"

    if [ -d "flutter" ] && command_exists flutter; then
        cd flutter
        print_info "Running flutter pub get..."
        flutter pub get
        print_success "Flutter dependencies installed"
        cd ..
    else
        print_warning "Flutter directory not found or Flutter not installed, skipping"
    fi
}

# Install React Native dependencies
setup_react_native() {
    print_header "Setting up React Native dependencies"

    if [ -d "react-native" ] && command_exists npm; then
        cd react-native
        if [ -f "package.json" ]; then
            print_info "Running npm install..."
            npm install
            print_success "React Native dependencies installed"
        fi
        cd ..
    else
        print_warning "React Native directory not found or npm not installed, skipping"
    fi
}

# Perform initial build
initial_build() {
    print_header "Performing initial build"

    read -p "Do you want to perform an initial build for your platform? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$OS" == "macos" ]]; then
            print_info "Building for macOS..."
            make build-macos BUILD_TYPE=Release || print_warning "Build failed, but setup can continue"
        elif [[ "$OS" == "linux" ]]; then
            print_info "Building for Linux..."
            make build-linux BUILD_TYPE=Release || print_warning "Build failed, but setup can continue"
        fi
    else
        print_info "Skipping initial build"
    fi
}

# Create necessary directories
create_directories() {
    print_header "Creating directory structure"

    mkdir -p build
    mkdir -p core/third_party
    mkdir -p docs
    mkdir -p examples

    print_success "Directories created"
}

# Generate compile_commands.json for IDE support
generate_compile_commands() {
    print_header "Generating compile_commands.json for IDE support"

    if [ -d "build/macos" ]; then
        if [ -f "build/macos/compile_commands.json" ]; then
            ln -sf build/macos/compile_commands.json compile_commands.json
            print_success "compile_commands.json linked"
        fi
    else
        print_info "Build directory not found, skipping"
    fi
}

# Print setup summary
print_summary() {
    echo ""
    print_header "Setup Summary"
    echo ""
    echo -e "${COLOR_BOLD}Next steps:${COLOR_RESET}"
    echo ""
    echo "  1. Build the project:"
    echo -e "     ${COLOR_GREEN}make build-macos${COLOR_RESET}      # macOS native"
    echo -e "     ${COLOR_GREEN}make build-ios${COLOR_RESET}        # iOS XCFramework"
    echo -e "     ${COLOR_GREEN}make build-android${COLOR_RESET}    # Android AAR"
    echo ""
    echo "  2. Run tests:"
    echo -e "     ${COLOR_GREEN}make test${COLOR_RESET}"
    echo ""
    echo "  3. View all available commands:"
    echo -e "     ${COLOR_GREEN}make help${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_BOLD}Documentation:${COLOR_RESET}"
    echo "  • README.md - Project overview"
    echo "  • docs/ - Detailed documentation (coming soon)"
    echo ""
    print_success "Setup complete! Happy coding!"
    echo ""
}

# Main setup flow
main() {
    print_banner

    # Detect OS
    detect_os
    print_info "Detected OS: $OS"
    echo ""

    # Check dependencies
    DEPS_OK=true

    check_cmake || DEPS_OK=false
    check_ninja || true  # Optional
    check_ccache || true  # Optional
    check_python || true  # Optional

    if [[ "$OS" == "macos" ]]; then
        check_xcode || DEPS_OK=false
        check_swift || DEPS_OK=false
    fi

    check_flutter || print_warning "Flutter not available"
    check_android_ndk || print_warning "Android NDK not available"
    check_nodejs || print_warning "Node.js not available"

    echo ""

    if [ "$DEPS_OK" = false ]; then
        print_error "Some required dependencies are missing"
        print_info "Please install missing dependencies and run this script again"
        exit 1
    fi

    print_success "All required dependencies found!"
    echo ""

    # Setup project
    create_directories
    setup_submodules
    setup_flutter
    setup_react_native

    echo ""

    # Optional initial build
    initial_build

    # Generate IDE support files
    generate_compile_commands

    # Print summary
    print_summary
}

# Run main function
main "$@"
