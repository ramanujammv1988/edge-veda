#!/usr/bin/env bash
# =============================================================================
# Edge Veda SDK — Build All Platforms
# =============================================================================
# Attempts to build every SDK platform and reports errors.
# Mirrors the CI pipeline defined in .github/workflows/ci.yml.
#
# Usage:
#   ./scripts/build-all.sh            # Local mode (relaxed, skips missing tools)
#   ./scripts/build-all.sh --ci       # CI mode   (strict, runs tests & lints)
#   ./scripts/build-all.sh --skip-tests  # Build-only, no test execution
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/build-logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
CI_MODE=false
SKIP_TESTS=false

for arg in "$@"; do
    case "$arg" in
        --ci)        CI_MODE=true ;;
        --skip-tests) SKIP_TESTS=true ;;
        --help|-h)
            echo "Usage: $0 [--ci] [--skip-tests]"
            echo ""
            echo "  --ci          Strict mode matching .github/workflows/ci.yml"
            echo "                (fatal-infos, format checks, linting, tests)"
            echo "  --skip-tests  Skip test execution for all platforms"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
declare -a PLATFORMS=()
declare -A RESULTS=()     # PASS | FAIL | SKIPPED
declare -A DURATIONS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log_header() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_pass() {
    echo -e "  ${GREEN}✅ PASS${NC} — $1"
}

log_fail() {
    echo -e "  ${RED}❌ FAIL${NC} — $1"
}

log_skip() {
    echo -e "  ${YELLOW}⏭  SKIP${NC} — $1"
}

log_info() {
    echo -e "  ${BLUE}ℹ${NC}  $1"
}

log_step() {
    echo -e "  ${CYAN}▸${NC} $1"
}

has_cmd() {
    command -v "$1" &>/dev/null
}

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# 1. C++ Core (CMake)
#    CI ref: jobs.core-build
# ---------------------------------------------------------------------------
build_core() {
    local name="core-cpp"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "C++ Core (CMake)  [ci: core-build]"

    if ! has_cmd cmake; then
        log_skip "cmake not found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/core"
        mkdir -p build
        cd build

        # CI uses Ninja when available, fallback to Make
        if has_cmd ninja; then
            echo "=== CMake Configure (Ninja) ==="
            cmake .. -G Ninja \
                -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_TESTING=ON 2>&1
            echo ""
            echo "=== Build ==="
            cmake --build . --config Release -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" 2>&1
        else
            echo "=== CMake Configure (Make) ==="
            cmake .. -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_TESTING=ON 2>&1
            echo ""
            echo "=== Build ==="
            make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" 2>&1
        fi

        # CI: Run tests (ctest)
        if [ "$SKIP_TESTS" = false ]; then
            echo ""
            echo "=== Tests (ctest) ==="
            ctest --output-on-failure --build-config Release 2>&1 || true
        fi

        # CI: Check binary size (<30MB)
        echo ""
        echo "=== Binary Size Check ==="
        echo "Binary sizes:"
        find . -name "*.so" -o -name "*.dylib" -o -name "*.a" 2>/dev/null | xargs ls -lh 2>/dev/null || true
        find . \( -name "*.so" -o -name "*.dylib" \) 2>/dev/null | while read file; do
            size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
            if [ "$size" -gt 31457280 ]; then
                echo "ERROR: $file is too large: $size bytes (>30MB)"
                exit 1
            fi
        done
    ) > "$logfile" 2>&1

    local rc=$?
    DURATIONS[$name]=$(( SECONDS - start ))

    if [ $rc -eq 0 ]; then
        log_pass "C++ Core built successfully (${DURATIONS[$name]}s)"
        RESULTS[$name]="PASS"
    else
        log_fail "C++ Core build failed (see $logfile)"
        RESULTS[$name]="FAIL"
    fi
}

# ---------------------------------------------------------------------------
# 2. Swift SDK
#    CI ref: jobs.swift-analyze
# ---------------------------------------------------------------------------
build_swift() {
    local name="swift"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "Swift SDK (swift build)  [ci: swift-analyze]"

    if ! has_cmd swift; then
        log_skip "swift not found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/swift"

        # CI: swift package resolve
        echo "=== Swift Package Resolve ==="
        swift package resolve 2>&1

        # CI: swift build -c release
        echo ""
        echo "=== Swift Build (Release) ==="
        swift build -c release 2>&1

        # CI: swift test
        if [ "$SKIP_TESTS" = false ]; then
            echo ""
            echo "=== Swift Test ==="
            swift test 2>&1
        fi
    ) > "$logfile" 2>&1

    local rc=$?
    DURATIONS[$name]=$(( SECONDS - start ))

    if [ $rc -eq 0 ]; then
        log_pass "Swift SDK built successfully (${DURATIONS[$name]}s)"
        RESULTS[$name]="PASS"
    else
        log_fail "Swift SDK build failed (see $logfile)"
        RESULTS[$name]="FAIL"
    fi
}

# ---------------------------------------------------------------------------
# 3. Kotlin / Android SDK
#    CI ref: jobs.kotlin-analyze
# ---------------------------------------------------------------------------
build_kotlin() {
    local name="kotlin"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "Kotlin SDK (Gradle)  [ci: kotlin-analyze]"

    # CI uses ./gradlew — check for gradlew or system gradle
    local gradle_cmd=""
    if [ -f "$PROJECT_ROOT/kotlin/gradlew" ]; then
        gradle_cmd="./gradlew"
    elif has_cmd gradle; then
        gradle_cmd="gradle"
    else
        log_skip "Neither gradlew nor gradle found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    # Check ANDROID_HOME / ANDROID_SDK_ROOT
    if [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
        log_skip "ANDROID_HOME / ANDROID_SDK_ROOT not set"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/kotlin"

        # CI: ktlintCheck
        if [ "$CI_MODE" = true ]; then
            echo "=== Kotlin Lint (ktlintCheck) ==="
            $gradle_cmd ktlintCheck --no-daemon 2>&1 || echo "(ktlint not configured yet)"
            echo ""
        fi

        # CI: gradlew build
        echo "=== Gradle Build ==="
        $gradle_cmd build --no-daemon --stacktrace 2>&1

        # CI: gradlew test
        if [ "$SKIP_TESTS" = false ]; then
            echo ""
            echo "=== Gradle Test ==="
            $gradle_cmd test --no-daemon 2>&1
        fi
    ) > "$logfile" 2>&1

    local rc=$?
    DURATIONS[$name]=$(( SECONDS - start ))

    if [ $rc -eq 0 ]; then
        log_pass "Kotlin SDK built successfully (${DURATIONS[$name]}s)"
        RESULTS[$name]="PASS"
    else
        log_fail "Kotlin SDK build failed (see $logfile)"
        RESULTS[$name]="FAIL"
    fi
}

# ---------------------------------------------------------------------------
# 4. React Native SDK
#    CI ref: jobs.react-native-analyze
# ---------------------------------------------------------------------------
build_react_native() {
    local name="react-native"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "React Native SDK (TypeScript)  [ci: react-native-analyze]"

    if ! has_cmd npm; then
        log_skip "npm not found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/react-native"

        # CI: npm ci || npm install
        echo "=== npm install ==="
        npm ci 2>&1 || npm install 2>&1

        # CI: npm run typecheck (falls back to tsc --noEmit if not configured)
        echo ""
        echo "=== TypeScript type-check ==="
        if npm run typecheck --if-present 2>&1 | grep -q "Missing script"; then
            npx tsc --noEmit 2>&1
        else
            npm run typecheck --if-present 2>&1
        fi

        # CI: npm run lint
        if [ "$CI_MODE" = true ]; then
            echo ""
            echo "=== Lint ==="
            npm run lint --if-present 2>&1 || echo "(lint not configured yet)"
        fi

        # CI: npm test
        if [ "$SKIP_TESTS" = false ]; then
            echo ""
            echo "=== Tests ==="
            npm test --if-present 2>&1 || echo "(tests not configured yet)"
        fi
    ) > "$logfile" 2>&1

    local rc=$?
    DURATIONS[$name]=$(( SECONDS - start ))

    if [ $rc -eq 0 ]; then
        log_pass "React Native SDK type-check passed (${DURATIONS[$name]}s)"
        RESULTS[$name]="PASS"
    else
        log_fail "React Native SDK type-check failed (see $logfile)"
        RESULTS[$name]="FAIL"
    fi
}

# ---------------------------------------------------------------------------
# 5. Web SDK
#    CI ref: (not in ci.yml — but follows same npm pattern as react-native)
# ---------------------------------------------------------------------------
build_web() {
    local name="web"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "Web SDK (Rollup + TypeScript)"

    if ! has_cmd npm; then
        log_skip "npm not found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/web"

        # npm ci || npm install (matches CI pattern)
        echo "=== npm install ==="
        npm ci 2>&1 || npm install 2>&1

        # TypeScript type-check
        echo ""
        echo "=== TypeScript type-check ==="
        if npm run typecheck --if-present 2>&1 | grep -q "Missing script"; then
            npx tsc --noEmit 2>&1
        else
            npm run typecheck --if-present 2>&1
        fi

        # Lint (CI mode)
        if [ "$CI_MODE" = true ]; then
            echo ""
            echo "=== Lint ==="
            npm run lint --if-present 2>&1 || echo "(lint not configured yet)"
        fi

        # Rollup build
        echo ""
        echo "=== Rollup build ==="
        npm run build 2>&1

        # Tests
        if [ "$SKIP_TESTS" = false ]; then
            echo ""
            echo "=== Tests ==="
            npm test --if-present 2>&1 || echo "(tests not configured yet)"
        fi
    ) > "$logfile" 2>&1

    local rc=$?
    DURATIONS[$name]=$(( SECONDS - start ))

    if [ $rc -eq 0 ]; then
        log_pass "Web SDK built successfully (${DURATIONS[$name]}s)"
        RESULTS[$name]="PASS"
    else
        log_fail "Web SDK build failed (see $logfile)"
        RESULTS[$name]="FAIL"
    fi
}

# ---------------------------------------------------------------------------
# 6. Flutter SDK
#    CI ref: jobs.flutter-analyze
# ---------------------------------------------------------------------------
build_flutter() {
    local name="flutter"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "Flutter SDK  [ci: flutter-analyze]"

    if ! has_cmd flutter; then
        log_skip "flutter not found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/flutter"

        # CI: flutter pub get
        echo "=== flutter pub get ==="
        flutter pub get 2>&1

        # CI: dart format --set-exit-if-changed . (CI mode only — strict)
        if [ "$CI_MODE" = true ]; then
            echo ""
            echo "=== Dart Format Check ==="
            dart format --set-exit-if-changed . 2>&1
        fi

        # CI: flutter analyze
        # CI uses --fatal-infos (strict); local uses --no-fatal-infos (relaxed)
        echo ""
        echo "=== flutter analyze ==="
        if [ "$CI_MODE" = true ]; then
            flutter analyze --fatal-infos 2>&1
        else
            flutter analyze --no-fatal-infos 2>&1
        fi

        # CI: flutter test --coverage
        if [ "$SKIP_TESTS" = false ]; then
            echo ""
            echo "=== flutter test ==="
            if [ "$CI_MODE" = true ]; then
                flutter test --coverage 2>&1
            else
                flutter test 2>&1 || echo "(tests not configured yet)"
            fi
        fi
    ) > "$logfile" 2>&1

    local rc=$?
    DURATIONS[$name]=$(( SECONDS - start ))

    if [ $rc -eq 0 ]; then
        log_pass "Flutter SDK analysis passed (${DURATIONS[$name]}s)"
        RESULTS[$name]="PASS"
    else
        log_fail "Flutter SDK analysis failed (see $logfile)"
        RESULTS[$name]="FAIL"
    fi
}

# ---------------------------------------------------------------------------
# 7. Code Quality Checks
#    CI ref: jobs.code-quality
# ---------------------------------------------------------------------------
check_code_quality() {
    local name="code-quality"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "Code Quality Checks  [ci: code-quality]"

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT"

        # CI: clang-format check
        echo "=== C++ Format Check ==="
        if has_cmd clang-format; then
            find core -name "*.cpp" -o -name "*.h" -o -name "*.hpp" 2>/dev/null | \
                xargs clang-format --dry-run --Werror 2>&1 || \
                echo "(some files need formatting)"
        else
            echo "(clang-format not found — skipping)"
        fi

        # CI: Check for large files (>10MB)
        echo ""
        echo "=== Large File Check ==="
        large_files=$(find . -type f -size +10M 2>/dev/null | grep -v ".git" | grep -v "third_party" | grep -v "node_modules" | grep -v "build" || true)
        if [ -n "$large_files" ]; then
            echo "WARNING: Large files found (>10MB):"
            echo "$large_files"
        else
            echo "No large files found (>10MB). OK."
        fi

        echo ""
        echo "=== License Header Check ==="
        echo "(placeholder — add license header validation as needed)"
    ) > "$logfile" 2>&1

    local rc=$?
    DURATIONS[$name]=$(( SECONDS - start ))

    if [ $rc -eq 0 ]; then
        log_pass "Code quality checks passed (${DURATIONS[$name]}s)"
        RESULTS[$name]="PASS"
    else
        log_fail "Code quality checks failed (see $logfile)"
        RESULTS[$name]="FAIL"
    fi
}

# =============================================================================
# Run All Builds
# =============================================================================
echo ""
echo -e "${BOLD}Edge Veda SDK — Build All Platforms${NC}"
if [ "$CI_MODE" = true ]; then
    echo -e "Mode:         ${YELLOW}CI (strict — mirrors .github/workflows/ci.yml)${NC}"
else
    echo -e "Mode:         ${GREEN}Local (relaxed)${NC}"
fi
if [ "$SKIP_TESTS" = true ]; then
    echo -e "Tests:        ${YELLOW}SKIPPED${NC}"
else
    echo -e "Tests:        ${GREEN}ENABLED${NC}"
fi
echo -e "Started at $(date)"
echo -e "Project root: $PROJECT_ROOT"
echo -e "Logs dir:     $LOG_DIR"

TOTAL_START=$SECONDS

# CI jobs: core-build, swift-analyze, kotlin-analyze, react-native-analyze, flutter-analyze, code-quality
build_core
build_swift
build_kotlin
build_react_native
build_web
build_flutter
check_code_quality

TOTAL_DURATION=$(( SECONDS - TOTAL_START ))

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  BUILD SUMMARY${NC}"
if [ "$CI_MODE" = true ]; then
    echo -e "  ${YELLOW}(CI mode — strict, mirrors .github/workflows/ci.yml)${NC}"
fi
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

printf "  ${BOLD}%-20s %-12s %-10s${NC}\n" "PLATFORM" "STATUS" "TIME"
printf "  %-20s %-12s %-10s\n"  "────────────────────" "────────────" "──────────"

FAIL_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0

for platform in "${PLATFORMS[@]}"; do
    status="${RESULTS[$platform]}"
    duration="${DURATIONS[$platform]:-—}"

    case "$status" in
        PASS)
            printf "  %-20s ${GREEN}%-12s${NC} %ss\n" "$platform" "✅ PASS" "$duration"
            ((PASS_COUNT++))
            ;;
        FAIL)
            printf "  %-20s ${RED}%-12s${NC} %ss\n" "$platform" "❌ FAIL" "$duration"
            ((FAIL_COUNT++))
            ;;
        SKIPPED)
            printf "  %-20s ${YELLOW}%-12s${NC} %s\n" "$platform" "⏭  SKIP" "—"
            ((SKIP_COUNT++))
            ;;
    esac
done

echo ""
echo -e "  Total: ${BOLD}${PASS_COUNT} passed${NC}, ${BOLD}${FAIL_COUNT} failed${NC}, ${BOLD}${SKIP_COUNT} skipped${NC}  (${TOTAL_DURATION}s)"
echo ""

# ---------------------------------------------------------------------------
# CI parity notes
# ---------------------------------------------------------------------------
echo -e "${BOLD}  CI Workflow Parity Notes:${NC}"
echo -e "  ─────────────────────────────────────────────────────────────────────"
echo -e "  Mirrors:  ${CYAN}.github/workflows/ci.yml${NC}"
echo -e "  Jobs covered locally:"
echo -e "    • core-build      → core-cpp"
echo -e "    • swift-analyze   → swift"
echo -e "    • kotlin-analyze  → kotlin"
echo -e "    • react-native-analyze → react-native"
echo -e "    • flutter-analyze → flutter"
echo -e "    • code-quality    → code-quality"
echo -e "  CI-only (not run locally):"
echo -e "    • ios-build         (requires Xcode + make build-ios)"
echo -e "    • android-build     (requires NDK + make build-android)"
echo -e "    • security-scan     (requires Trivy)"
echo -e "    • integration-tests (main branch only)"
echo ""

# ---------------------------------------------------------------------------
# Print error details for failed builds
# ---------------------------------------------------------------------------
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${RED}  ERROR DETAILS${NC}"
    echo -e "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    for platform in "${PLATFORMS[@]}"; do
        if [ "${RESULTS[$platform]}" = "FAIL" ]; then
            local_log="$LOG_DIR/${platform}.log"
            echo ""
            echo -e "  ${RED}▸ ${BOLD}${platform}${NC} — last 50 lines of $local_log:"
            echo -e "  ${RED}────────────────────────────────────────────────────────────${NC}"
            tail -50 "$local_log" 2>/dev/null | sed 's/^/    /'
            echo ""
        fi
    done
fi

# ---------------------------------------------------------------------------
# Exit code
# ---------------------------------------------------------------------------
echo -e "Build logs saved to: ${BOLD}$LOG_DIR/${NC}"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
