---
phase: 05-cicd-testing-infrastructure
plan: 01
subsystem: ci-cd
tags: [ndk, ci-consistency, codecov, coverage, testing-infrastructure]

dependency_graph:
  requires: []
  provides: [consistent-ndk-version, clear-ci-labels, codecov-pr-comments]
  affects: [ci-workflow, android-builds, code-coverage]

tech_stack:
  added: [codecov-yaml-config]
  patterns: [ci-version-pinning, optional-job-labeling, pr-coverage-comments]

key_files:
  created:
    - codecov.yml
  modified:
    - .github/workflows/ci.yml

decisions:
  - NDK r27c (27.2.12479018) is the canonical version across all build configurations
  - iOS and Android CI jobs are clearly labeled as optional to avoid confusion
  - Codecov thresholds: 1% project regression allowed, 80% patch coverage target
  - Coverage comments include diff, flags, and file-level breakdown for PR visibility

metrics:
  duration: 183
  completed: 2026-02-28T22:41:26Z
---

# Phase 05 Plan 01: CI Configuration Consistency Summary

**One-liner:** Fixed NDK version inconsistency (r27c everywhere) and configured Codecov for PR coverage visibility with 80% patch target.

## What Was Built

### Task 1: Fix NDK version consistency and label optional CI jobs
- **Status:** ✓ Complete
- **Commit:** 988e0b5
- **Files:** .github/workflows/ci.yml

Fixed NDK version mismatch where ci.yml had r26c while build.gradle and build-android.sh had r27c. Updated ci.yml to use NDK_VERSION '27.2.12479018' (r27c) consistently. Also clarified that iOS and Android build jobs are optional/non-blocking by:
- Renaming job names to include "(optional - requires Xcode Metal)" and "(optional - requires NDK)"
- Updating comments to say "OPTIONAL / NON-BLOCKING:"
- Adding ios-build and android-build to build-summary needs array with explicit status reporting

### Task 2: Create Codecov configuration for PR coverage comments
- **Status:** ✓ Complete
- **Commit:** 03e2880
- **Files:** codecov.yml (created)

Created codecov.yml with:
- Project coverage: auto-track with 1% regression threshold before failing
- Patch coverage: 80% target for new code in PRs
- PR comment configuration: layout shows reach, diff, flags, and files
- Flutter flag matching ci.yml upload with carryforward enabled
- Ignore patterns for generated files (generated_bindings.dart, *.g.dart, *.freezed.dart) and third-party code

## Deviations from Plan

None - plan executed exactly as written.

## Authentication Gates

None.

## Verification Results

All verification checks passed:
- ✓ No old NDK versions (26.1.10909125 or r26c) remain in ci.yml
- ✓ Two "optional" labels found in job names (iOS and Android)
- ✓ codecov.yml exists at repo root
- ✓ ci.yml is valid YAML
- ✓ codecov.yml is valid YAML

## Success Criteria

All criteria met:
- ✓ NDK version is 27.2.12479018 / r27c in all three files (ci.yml, build-android.sh, build.gradle)
- ✓ iOS and Android CI jobs have names containing "optional"
- ✓ build-summary reports status of all four jobs (core-build, flutter-analyze, ios-build, android-build)
- ✓ codecov.yml configures PR comments with coverage trends

## Self-Check

Verifying all files and commits exist:

- FOUND: .github/workflows/ci.yml
- FOUND: codecov.yml
- FOUND: 988e0b5 (Task 1 commit)
- FOUND: 03e2880 (Task 2 commit)

**Self-Check: PASSED**
