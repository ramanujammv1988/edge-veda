---
phase: 04-release
plan: 02
subsystem: infra
tags: [github-actions, pub-dev, xcframework, ci-cd, release-automation]

# Dependency graph
requires:
  - phase: 04-01
    provides: prepare-release.sh validation script, version sync across files
  - phase: 01-03
    provides: build-ios.sh XCFramework build script
provides:
  - GitHub Actions release workflow (release.yml)
  - Automated tag-triggered releases
  - XCFramework build and GitHub Release creation
  - pub.dev publish pipeline (pending PUB_TOKEN)
affects: [future-releases, documentation]

# Tech tracking
tech-stack:
  added: [softprops/action-gh-release, pana]
  patterns: [tag-triggered-releases, multi-job-workflow, sequential-job-dependencies]

key-files:
  created:
    - .github/workflows/release.yml
  modified: []

key-decisions:
  - "PUB_TOKEN deferred - first release will be manual"
  - "Three-job workflow: validate -> build-release -> publish"
  - "Prerelease detection via version suffix (contains -)"

patterns-established:
  - "Release workflow: validate-release -> build-and-release-xcframework -> publish-to-pub-dev"
  - "XCFramework distributed via GitHub Releases ZIP download"
  - "Changelog extraction for release notes"

# Metrics
duration: 44min
completed: 2026-02-04
---

# Phase 4 Plan 2: Release Workflow Summary

**GitHub Actions workflow for tag-triggered releases with XCFramework builds, GitHub Releases, and pub.dev publishing pipeline**

## Performance

- **Duration:** 44 min
- **Started:** 2026-02-04T19:20:22Z
- **Completed:** 2026-02-04T20:04:XX Z
- **Tasks:** 3
- **Files created:** 1

## Accomplishments
- Created complete release workflow with 3 jobs and proper dependency chain
- Integrated existing prepare-release.sh for version validation
- Automated XCFramework build and GitHub Release creation with changelog extraction
- Set up pub.dev publishing pipeline with pana validation (pending PUB_TOKEN secret)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create release.yml workflow** - `05af835` (feat)
2. **Task 2: Configure PUB_TOKEN secret** - *skipped by user* (manual publish preferred for v1.0.0)
3. **Task 3: Validate workflow syntax** - *validation only* (YAML fix included in Task 1 commit)

**Plan metadata:** pending

## Files Created/Modified
- `.github/workflows/release.yml` - Complete release workflow (299 lines)

## Workflow Structure

```
on: push tags: v*

validate-release (ubuntu-latest, 10min timeout)
  |-- Checkout + Flutter setup
  |-- Extract version from tag
  |-- Run prepare-release.sh validation
  |-- Output: version

build-and-release-xcframework (macos-latest, 45min timeout)
  |-- needs: validate-release
  |-- Checkout + Xcode + CMake/Ninja
  |-- Run build-ios.sh --clean --release
  |-- Verify XCFramework size (<30MB)
  |-- Create ZIP archive
  |-- Extract release notes from CHANGELOG
  |-- Create GitHub Release with XCFramework

publish-to-pub-dev (ubuntu-latest, 10min timeout)
  |-- needs: build-and-release-xcframework
  |-- Flutter setup + pub get
  |-- pana validation (score check)
  |-- Setup credentials from PUB_TOKEN
  |-- dart pub publish --force
```

## Decisions Made
- **PUB_TOKEN deferred:** User will publish v1.0.0 manually, automated publishing configured for future releases
- **Three sequential jobs:** Validate first (fast fail), then expensive build, then publish
- **Prerelease detection:** Uses `contains(version, '-')` to mark prereleases automatically
- **XCFramework size limit:** 30MB hard limit with clear error messages

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed YAML syntax error in multiline string**
- **Found during:** Task 3 (workflow validation)
- **Issue:** Multiline string assignment in bash script confused YAML parser (line 142-144)
- **Fix:** Changed to heredoc-style default message generation
- **Files modified:** .github/workflows/release.yml
- **Verification:** `python3 -c "import yaml; yaml.safe_load(...)"` passes
- **Committed in:** 05af835 (amended Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Bug fix required for valid YAML. No scope creep.

## Issues Encountered
- YAML parser issue with embedded newlines in bash multiline strings - resolved by using heredoc

## User Setup Required

**PUB_TOKEN secret deferred.** For automated publishing in future releases:

1. Generate token at pub.dev (Account -> Publishing Access -> Create Token)
2. Add to GitHub Secrets as `PUB_TOKEN`
3. Re-run failed publish job or trigger new release

For v1.0.0: Manual publish via `cd flutter && dart pub publish`

## Next Phase Readiness
- Release workflow ready for tag-triggered releases
- XCFramework will be built and uploaded automatically
- Manual publish for v1.0.0, automated for subsequent releases
- Phase 4 complete - project ready for initial release

---
*Phase: 04-release*
*Completed: 2026-02-04*
