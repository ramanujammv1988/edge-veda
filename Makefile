# Edge Veda SDK - Master Makefile
# Cross-platform build orchestration for C++ core and native wrappers

# Project configuration
PROJECT_NAME := EdgeVeda
VERSION := 0.1.0
BUILD_DIR := build
CORE_DIR := core
FLUTTER_DIR := flutter
SWIFT_DIR := swift
KOTLIN_DIR := kotlin
RN_DIR := react-native
WEB_DIR := web

# Build configuration
BUILD_TYPE ?= Release
NUM_JOBS ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
CMAKE ?= cmake
NINJA ?= ninja

# iOS configuration
IOS_DEPLOYMENT_TARGET ?= 13.0
IOS_PLATFORM ?= OS64
IOS_SIMULATOR_PLATFORM ?= SIMULATORARM64

# Android configuration
ANDROID_ABI ?= arm64-v8a
ANDROID_PLATFORM ?= android-24
ANDROID_STL ?= c++_shared
ANDROID_NDK ?= $(shell echo $$ANDROID_NDK_HOME)

# Emscripten configuration
EMSDK ?= $(shell echo $$EMSDK)
EMSCRIPTEN ?= $(EMSDK)/upstream/emscripten

# Colors for output
COLOR_RESET := \033[0m
COLOR_BOLD := \033[1m
COLOR_GREEN := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE := \033[34m

# Helper function for colored output
define print_header
	@echo "$(COLOR_BOLD)$(COLOR_BLUE)==> $(1)$(COLOR_RESET)"
endef

define print_success
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ $(1)$(COLOR_RESET)"
endef

define print_warning
	@echo "$(COLOR_BOLD)$(COLOR_YELLOW)⚠ $(1)$(COLOR_RESET)"
endef

.PHONY: all help clean test format check \
	build-macos build-macos-framework build-ios build-android build-wasm \
	build-flutter build-swift build-kotlin build-rn \
	install-deps setup

# Default target
all: build-macos

# Help target
help:
	@echo "$(COLOR_BOLD)Edge Veda SDK - Build System$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Platform Targets:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)build-macos$(COLOR_RESET)      - Build C++ core for macOS"
	@echo "  $(COLOR_GREEN)build-macos-framework$(COLOR_RESET) - Build macOS XCFramework for Flutter"
	@echo "  $(COLOR_GREEN)build-ios$(COLOR_RESET)        - Build iOS XCFramework (device + simulator)"
	@echo "  $(COLOR_GREEN)build-android$(COLOR_RESET)    - Build Android AAR for all ABIs"
	@echo "  $(COLOR_GREEN)build-wasm$(COLOR_RESET)       - Build WebAssembly module"
	@echo ""
	@echo "$(COLOR_BOLD)SDK Targets:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)build-flutter$(COLOR_RESET)    - Build Flutter plugin"
	@echo "  $(COLOR_GREEN)build-swift$(COLOR_RESET)      - Build Swift package"
	@echo "  $(COLOR_GREEN)build-kotlin$(COLOR_RESET)     - Build Kotlin SDK"
	@echo "  $(COLOR_GREEN)build-rn$(COLOR_RESET)         - Build React Native module"
	@echo ""
	@echo "$(COLOR_BOLD)Development Targets:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)test$(COLOR_RESET)             - Run all tests"
	@echo "  $(COLOR_GREEN)format$(COLOR_RESET)           - Format all source code"
	@echo "  $(COLOR_GREEN)check$(COLOR_RESET)            - Run static analysis"
	@echo "  $(COLOR_GREEN)clean$(COLOR_RESET)            - Clean all build artifacts"
	@echo "  $(COLOR_GREEN)setup$(COLOR_RESET)            - Run initial project setup"
	@echo ""
	@echo "$(COLOR_BOLD)Configuration:$(COLOR_RESET)"
	@echo "  BUILD_TYPE=$(BUILD_TYPE)"
	@echo "  NUM_JOBS=$(NUM_JOBS)"
	@echo "  ANDROID_NDK=$(ANDROID_NDK)"

# ============================================================================
# macOS Build
# ============================================================================
build-macos:
	$(call print_header,"Building C++ Core for macOS")
	@mkdir -p $(BUILD_DIR)/macos
	@cd $(BUILD_DIR)/macos && \
		$(CMAKE) ../../$(CORE_DIR) \
			-G Ninja \
			-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
			-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
			-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
			-DEDGE_VEDA_ENABLE_METAL=ON \
			-DEDGE_VEDA_BUILD_STATIC=ON \
			-DBUILD_TESTING=ON
	@cd $(BUILD_DIR)/macos && $(NINJA) -j $(NUM_JOBS)
	$(call print_success,"macOS build complete: $(BUILD_DIR)/macos/")

build-macos-framework:
	$(call print_header,"Building macOS XCFramework via build-macos.sh")
	@./scripts/build-macos.sh --clean --release
	$(call print_success,"macOS XCFramework built")

# ============================================================================
# iOS Build
# ============================================================================
build-ios: build-ios-device build-ios-simulator create-xcframework

build-ios-device:
	$(call print_header,"Building C++ Core for iOS Device")
	@mkdir -p $(BUILD_DIR)/ios-device
	@cd $(BUILD_DIR)/ios-device && \
		$(CMAKE) ../../$(CORE_DIR) \
			-G Ninja \
			-DCMAKE_TOOLCHAIN_FILE=../../$(CORE_DIR)/cmake/ios.toolchain.cmake \
			-DPLATFORM=$(IOS_PLATFORM) \
			-DDEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET) \
			-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
			-DUSE_METAL=ON \
			-DBUILD_SHARED_LIBS=OFF
	@cd $(BUILD_DIR)/ios-device && $(NINJA) -j $(NUM_JOBS)
	$(call print_success,"iOS device build complete")

build-ios-simulator:
	$(call print_header,"Building C++ Core for iOS Simulator")
	@mkdir -p $(BUILD_DIR)/ios-simulator
	@cd $(BUILD_DIR)/ios-simulator && \
		$(CMAKE) ../../$(CORE_DIR) \
			-G Ninja \
			-DCMAKE_TOOLCHAIN_FILE=../../$(CORE_DIR)/cmake/ios.toolchain.cmake \
			-DPLATFORM=$(IOS_SIMULATOR_PLATFORM) \
			-DDEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET) \
			-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
			-DBUILD_SHARED_LIBS=OFF
	@cd $(BUILD_DIR)/ios-simulator && $(NINJA) -j $(NUM_JOBS)
	$(call print_success,"iOS simulator build complete")

create-xcframework:
	$(call print_header,"Creating iOS XCFramework")
	@mkdir -p $(BUILD_DIR)/ios
	@if [ -d "$(BUILD_DIR)/ios/$(PROJECT_NAME).xcframework" ]; then \
		rm -rf $(BUILD_DIR)/ios/$(PROJECT_NAME).xcframework; \
	fi
	@xcodebuild -create-xcframework \
		-library $(BUILD_DIR)/ios-device/lib$(PROJECT_NAME).a \
		-headers $(CORE_DIR)/include \
		-library $(BUILD_DIR)/ios-simulator/lib$(PROJECT_NAME).a \
		-headers $(CORE_DIR)/include \
		-output $(BUILD_DIR)/ios/$(PROJECT_NAME).xcframework
	$(call print_success,"XCFramework created: $(BUILD_DIR)/ios/$(PROJECT_NAME).xcframework")

# ============================================================================
# Android Build
# ============================================================================
build-android: check-android-ndk
	$(call print_header,"Building C++ Core for Android (multi-ABI)")
	@for abi in arm64-v8a armeabi-v7a x86_64 x86; do \
		echo "$(COLOR_BOLD)Building for ABI: $$abi$(COLOR_RESET)"; \
		mkdir -p $(BUILD_DIR)/android/$$abi; \
		cd $(BUILD_DIR)/android/$$abi && \
		$(CMAKE) ../../../$(CORE_DIR) \
			-G Ninja \
			-DCMAKE_TOOLCHAIN_FILE=../../../$(CORE_DIR)/cmake/android.toolchain.cmake \
			-DANDROID_ABI=$$abi \
			-DANDROID_PLATFORM=$(ANDROID_PLATFORM) \
			-DANDROID_STL=$(ANDROID_STL) \
			-DANDROID_NDK=$(ANDROID_NDK) \
			-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
			-DUSE_VULKAN=ON \
			-DBUILD_SHARED_LIBS=ON && \
		$(NINJA) -j $(NUM_JOBS) || exit 1; \
		cd ../../..; \
	done
	@$(MAKE) package-android-aar
	$(call print_success,"Android build complete: $(BUILD_DIR)/android/edgeveda.aar")

package-android-aar:
	$(call print_header,"Packaging Android AAR")
	@mkdir -p $(BUILD_DIR)/android/aar/jni
	@for abi in arm64-v8a armeabi-v7a x86_64 x86; do \
		mkdir -p $(BUILD_DIR)/android/aar/jni/$$abi; \
		cp $(BUILD_DIR)/android/$$abi/*.so $(BUILD_DIR)/android/aar/jni/$$abi/ 2>/dev/null || true; \
	done
	@cd $(BUILD_DIR)/android/aar && zip -r ../edgeveda.aar . > /dev/null
	$(call print_success,"AAR packaged")

check-android-ndk:
	@if [ -z "$(ANDROID_NDK)" ] || [ ! -d "$(ANDROID_NDK)" ]; then \
		echo "$(COLOR_YELLOW)ERROR: ANDROID_NDK not found or invalid$(COLOR_RESET)"; \
		echo "Please set ANDROID_NDK_HOME environment variable"; \
		exit 1; \
	fi
	@echo "Using Android NDK: $(ANDROID_NDK)"

# ============================================================================
# WebAssembly Build
# ============================================================================
build-wasm: check-emscripten
	$(call print_header,"Building WebAssembly module")
	@mkdir -p $(BUILD_DIR)/wasm
	@. $(EMSDK)/emsdk_env.sh && \
		cd $(BUILD_DIR)/wasm && \
		emcmake $(CMAKE) ../../$(CORE_DIR) \
			-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
			-DBUILD_SHARED_LIBS=OFF \
			-DUSE_WEBGPU=ON && \
		emmake make -j $(NUM_JOBS)
	$(call print_success,"WASM build complete: $(BUILD_DIR)/wasm/")

check-emscripten:
	@if [ -z "$(EMSDK)" ] || [ ! -d "$(EMSDK)" ]; then \
		echo "$(COLOR_YELLOW)ERROR: Emscripten SDK not found$(COLOR_RESET)"; \
		echo "Please install Emscripten and set EMSDK environment variable"; \
		echo "Visit: https://emscripten.org/docs/getting_started/downloads.html"; \
		exit 1; \
	fi
	@echo "Using Emscripten SDK: $(EMSDK)"

# ============================================================================
# SDK Builds
# ============================================================================
build-flutter: build-macos
	$(call print_header,"Building Flutter plugin")
	@cd $(FLUTTER_DIR) && flutter pub get
	@cd $(FLUTTER_DIR) && dart format .
	@cd $(FLUTTER_DIR) && flutter analyze
	$(call print_success,"Flutter plugin ready")

build-swift: build-macos
	$(call print_header,"Building Swift package")
	@cd $(SWIFT_DIR) && swift build -c release
	$(call print_success,"Swift package built")

build-kotlin: build-android
	$(call print_header,"Building Kotlin SDK")
	@cd $(KOTLIN_DIR) && ./gradlew build || echo "Gradle not configured yet"
	$(call print_success,"Kotlin SDK built")

build-rn:
	$(call print_header,"Building React Native module")
	@cd $(RN_DIR) && npm install
	@cd $(RN_DIR) && npm run build || echo "Build script not configured yet"
	$(call print_success,"React Native module built")

# ============================================================================
# Testing
# ============================================================================
test: test-core test-flutter test-swift

test-core:
	$(call print_header,"Running C++ tests")
	@if [ -d "$(BUILD_DIR)/macos" ]; then \
		cd $(BUILD_DIR)/macos && ctest --output-on-failure; \
	else \
		echo "$(COLOR_YELLOW)macOS build not found. Run 'make build-macos' first$(COLOR_RESET)"; \
	fi

test-flutter:
	$(call print_header,"Running Flutter tests")
	@cd $(FLUTTER_DIR) && flutter test || echo "No Flutter tests configured yet"

test-swift:
	$(call print_header,"Running Swift tests")
	@cd $(SWIFT_DIR) && swift test || echo "No Swift tests configured yet"

test-android:
	$(call print_header,"Running Android tests")
	@cd $(KOTLIN_DIR) && ./gradlew test || echo "No Android tests configured yet"

test-rn:
	$(call print_header,"Running React Native tests")
	@cd $(RN_DIR) && npm test || echo "No RN tests configured yet"

# ============================================================================
# Code Formatting
# ============================================================================
format: format-cpp format-dart format-swift format-kotlin

format-cpp:
	$(call print_header,"Formatting C++ code")
	@find $(CORE_DIR) -name "*.cpp" -o -name "*.h" -o -name "*.hpp" | \
		xargs clang-format -i --style=file || \
		echo "$(COLOR_YELLOW)clang-format not found, skipping$(COLOR_RESET)"

format-dart:
	$(call print_header,"Formatting Dart code")
	@cd $(FLUTTER_DIR) && dart format .

format-swift:
	$(call print_header,"Formatting Swift code")
	@swiftformat $(SWIFT_DIR) || \
		echo "$(COLOR_YELLOW)swiftformat not found, skipping$(COLOR_RESET)"

format-kotlin:
	$(call print_header,"Formatting Kotlin code")
	@cd $(KOTLIN_DIR) && ./gradlew ktlintFormat || \
		echo "$(COLOR_YELLOW)ktlint not configured, skipping$(COLOR_RESET)"

# ============================================================================
# Static Analysis
# ============================================================================
check: check-cpp check-flutter

check-cpp:
	$(call print_header,"Running C++ static analysis")
	@clang-tidy $(CORE_DIR)/src/*.cpp -- -I$(CORE_DIR)/include || \
		echo "$(COLOR_YELLOW)clang-tidy not found, skipping$(COLOR_RESET)"

check-flutter:
	$(call print_header,"Running Flutter analysis")
	@cd $(FLUTTER_DIR) && flutter analyze

# ============================================================================
# Cleanup
# ============================================================================
clean:
	$(call print_header,"Cleaning build artifacts")
	@rm -rf $(BUILD_DIR)
	@cd $(FLUTTER_DIR) && flutter clean || true
	@cd $(SWIFT_DIR) && swift package clean || true
	@cd $(KOTLIN_DIR) && ./gradlew clean || true
	@cd $(RN_DIR) && rm -rf node_modules build || true
	$(call print_success,"Clean complete")

clean-all: clean
	$(call print_header,"Deep cleaning (including dependencies)")
	@cd $(FLUTTER_DIR) && rm -rf .dart_tool .packages || true
	@cd $(RN_DIR) && rm -rf node_modules package-lock.json || true
	$(call print_success,"Deep clean complete")

# ============================================================================
# Setup and Installation
# ============================================================================
setup:
	$(call print_header,"Running project setup")
	@./scripts/setup.sh

install-deps:
	$(call print_header,"Installing system dependencies")
	@if command -v brew >/dev/null 2>&1; then \
		brew install cmake ninja ccache clang-format; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && \
		sudo apt-get install -y cmake ninja-build ccache clang-format; \
	else \
		echo "$(COLOR_YELLOW)Unknown package manager. Please install dependencies manually.$(COLOR_RESET)"; \
	fi

# ============================================================================
# Version and Info
# ============================================================================
version:
	@echo "Edge Veda SDK v$(VERSION)"

info:
	@echo "$(COLOR_BOLD)Build Configuration:$(COLOR_RESET)"
	@echo "  Build Type: $(BUILD_TYPE)"
	@echo "  Jobs: $(NUM_JOBS)"
	@echo "  CMake: $(shell which cmake)"
	@echo "  Ninja: $(shell which ninja 2>/dev/null || echo 'not found')"
	@echo "  Android NDK: $(ANDROID_NDK)"
	@echo "  Emscripten: $(EMSDK)"

# ============================================================================
# CI/CD Helpers
# ============================================================================
ci-build-all:
	$(MAKE) build-macos BUILD_TYPE=Release
	$(MAKE) build-ios BUILD_TYPE=Release
	$(MAKE) build-android BUILD_TYPE=Release

ci-test-all:
	$(MAKE) test-core
	$(MAKE) test-flutter
	$(MAKE) test-swift
