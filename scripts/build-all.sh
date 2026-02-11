#!/usr/bin/env bash
# =============================================================================
# Edge Veda SDK — Build All Platforms
# =============================================================================
# Attempts to build every SDK platform and reports errors.
# Usage: ./scripts/build-all.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/build-logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

has_cmd() {
    command -v "$1" &>/dev/null
}

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# 1. C++ Core (CMake)
# ---------------------------------------------------------------------------
build_core() {
    local name="core-cpp"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "C++ Core (CMake)"

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
        cmake .. -DCMAKE_BUILD_TYPE=Release 2>&1
        make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" 2>&1
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
# ---------------------------------------------------------------------------
build_swift() {
    local name="swift"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "Swift SDK (swift build)"

    if ! has_cmd swift; then
        log_skip "swift not found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/swift"
        swift build 2>&1
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
# ---------------------------------------------------------------------------
build_kotlin() {
    local name="kotlin"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "Kotlin SDK (Gradle)"

    # Check for gradlew or system gradle
    local gradle_cmd=""
    if [ -f "$PROJECT_ROOT/kotlin/gradlew" ]; then
        gradle_cmd="$PROJECT_ROOT/kotlin/gradlew"
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
        $gradle_cmd build --no-daemon --stacktrace 2>&1
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
# 4. React Native SDK (TypeScript check)
# ---------------------------------------------------------------------------
build_react_native() {
    local name="react-native"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "React Native SDK (TypeScript)"

    if ! has_cmd npm; then
        log_skip "npm not found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/react-native"
        echo "=== npm install ==="
        npm install 2>&1
        echo ""
        echo "=== TypeScript type-check ==="
        npx tsc --noEmit 2>&1
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
# 5. Web SDK (Rollup build)
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
        echo "=== npm install ==="
        npm install 2>&1
        echo ""
        echo "=== TypeScript type-check ==="
        npx tsc --noEmit 2>&1
        echo ""
        echo "=== Rollup build ==="
        npm run build 2>&1
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
# ---------------------------------------------------------------------------
build_flutter() {
    local name="flutter"
    local logfile="$LOG_DIR/${name}.log"
    PLATFORMS+=("$name")

    log_header "Flutter SDK"

    if ! has_cmd flutter; then
        log_skip "flutter not found"
        RESULTS[$name]="SKIPPED"
        return
    fi

    local start=$SECONDS
    (
        cd "$PROJECT_ROOT/flutter"
        echo "=== flutter pub get ==="
        flutter pub get 2>&1
        echo ""
        echo "=== flutter analyze ==="
        flutter analyze --no-fatal-infos 2>&1
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

# =============================================================================
# Run All Builds
# =============================================================================
echo ""
echo -e "${BOLD}Edge Veda SDK — Build All Platforms${NC}"
echo -e "Started at $(date)"
echo -e "Project root: $PROJECT_ROOT"
echo -e "Logs dir:     $LOG_DIR"

TOTAL_START=$SECONDS

build_core
build_swift
build_kotlin
build_react_native
build_web
build_flutter

TOTAL_DURATION=$(( SECONDS - TOTAL_START ))

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  BUILD SUMMARY${NC}"
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