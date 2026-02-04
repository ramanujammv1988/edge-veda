# Phase 4: Release - Research

**Researched:** 2026-02-04
**Domain:** Flutter plugin publishing, CI/CD, native binary distribution
**Confidence:** MEDIUM

## Summary

Publishing a Flutter plugin with native iOS dependencies to pub.dev presents unique challenges due to the XCFramework binary. The primary challenge: pub.dev has a **100MB compressed / 256MB uncompressed size limit**, and the XCFramework binary with llama.cpp libraries is ~15-20MB per architecture slice. This research identifies two viable approaches and recommends the modern Dart Native Assets approach which was stabilized in Flutter 3.38 (2025).

The project already has strong foundations: existing build scripts (`scripts/build-ios.sh`), CI workflow (`.github/workflows/ci.yml`), proper pubspec.yaml, LICENSE (MIT), CHANGELOG.md, and comprehensive README. The main gaps are XCFramework distribution strategy, version synchronization between podspec and pubspec, and release automation.

**Primary recommendation:** Use Dart Native Assets (`hook/build.dart`) to download the pre-built XCFramework from GitHub Releases during `pod install`. This keeps the pub.dev package small while automating binary distribution.

## Standard Stack

### Core Tools

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| pub.dev | - | Package registry | Only official registry for Dart/Flutter packages |
| GitHub Actions | v4 | CI/CD | Already configured, widely used, free for open source |
| GitHub Releases | - | Binary hosting | Free, reliable, integrates with CI, supports large files |
| pana | latest | Package scoring | Official tool used by pub.dev for scoring |
| CocoaPods | 1.9+ | iOS dependencies | Required for Flutter iOS plugins with xcframeworks |

### Supporting Tools

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `dart pub publish` | Package publishing | Final release step |
| `flutter pub publish --dry-run` | Pre-publish validation | Before every publish attempt |
| `xcodebuild -create-xcframework` | XCFramework creation | Already in build-ios.sh |
| `gh release create` | GitHub release automation | CI/CD release workflow |
| Codecov | Coverage reporting | Already configured in CI |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| GitHub Releases | AWS S3 / Cloudflare R2 | More setup, monthly costs, but higher bandwidth limits |
| Dart Native Assets | podspec `prepare_command` | Older approach, but more compatible with legacy projects |
| GitHub Actions | Codemagic / Bitrise | More features for mobile CI, but costs money |

## Architecture Patterns

### XCFramework Distribution Strategy

**CRITICAL DECISION:** The XCFramework cannot be included in the pub.dev package due to size limits.

#### Option A: Dart Native Assets (RECOMMENDED)

Since Flutter 3.38 and Dart 3.10, the `hook/build.dart` system is stable and recommended. This approach:

1. Creates a `hook/build.dart` file in the package
2. Downloads pre-built XCFramework from GitHub Releases during build
3. Bundles binary with the app automatically
4. No OS-specific build files needed

```dart
// hook/build.dart
import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'dart:io';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.target.os != OS.iOS) return;

    final version = '1.0.0'; // Read from pubspec
    final url = 'https://github.com/edgeveda/edge-veda-sdk/releases/download/v$version/EdgeVedaCore-ios.xcframework.zip';

    // Download and extract XCFramework
    final xcframeworkPath = await downloadAndExtract(url, input.outputDirectory);

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'lib/src/ffi/bindings.dart',
        linkMode: LookupInProcess(),
      ),
    );
  });
}
```

**Pros:**
- Modern, official Flutter approach
- Cross-platform consistent
- No podspec complexity for binary handling
- Works with `flutter pub get` automatically

**Cons:**
- Requires Flutter 3.38+
- Relatively new, less community examples

#### Option B: Podspec prepare_command (LEGACY)

Uses CocoaPods `prepare_command` to download during `pod install`:

```ruby
# edge_veda.podspec
s.prepare_command = <<-CMD
  FRAMEWORK_VERSION="1.0.0"
  FRAMEWORK_URL="https://github.com/edgeveda/edge-veda-sdk/releases/download/v${FRAMEWORK_VERSION}/EdgeVedaCore-ios.xcframework.zip"

  curl -L "$FRAMEWORK_URL" -o framework.zip
  unzip -o framework.zip -d Frameworks/
  rm framework.zip
CMD

s.vendored_frameworks = 'Frameworks/EdgeVedaCore.xcframework'
```

**Pros:**
- Works with any Flutter version
- Familiar to iOS developers
- Well-documented pattern

**Cons:**
- Only works when installed via `:path` (doesn't run for pub.dev packages)
- Need to use `vendored_frameworks` with HTTP source instead

#### Option C: Separate Pod (ALTERNATIVE)

Publish XCFramework as separate CocoaPods pod:

```ruby
# EdgeVedaCore.podspec (separate repo/release)
Pod::Spec.new do |s|
  s.name = 'EdgeVedaCore'
  s.version = '1.0.0'
  s.source = {
    :http => 'https://github.com/edgeveda/edge-veda-sdk/releases/download/v1.0.0/EdgeVedaCore-ios.xcframework.zip'
  }
  s.vendored_frameworks = 'EdgeVedaCore.xcframework'
  # ...
end

# In edge_veda.podspec
s.dependency 'EdgeVedaCore', '~> 1.0.0'
```

**Pros:**
- Clean separation of concerns
- CocoaPods handles download/caching
- Can be used independently of Flutter

**Cons:**
- Two packages to manage and version
- Must publish to CocoaPods trunk

### Release Workflow Structure

```
.github/
  workflows/
    ci.yml                 # Existing - analysis, tests
    release.yml            # NEW - triggered by tag

scripts/
  build-ios.sh             # Existing - builds XCFramework
  prepare-release.sh       # NEW - version bumping, changelog
```

### Version Synchronization

**CRITICAL:** Keep these in sync:
- `flutter/pubspec.yaml` version
- `flutter/ios/edge_veda.podspec` version
- `flutter/CHANGELOG.md` entry
- Git tag
- GitHub Release

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Package scoring | Manual checklist | `dart pub global run pana .` | Official tool, matches pub.dev exactly |
| CI caching | Custom cache logic | `hendrikmuhs/ccache-action@v1.2` | Already in CI, handles invalidation |
| Flutter setup | Manual installation | `subosito/flutter-action@v2` | Already in CI, handles versions |
| iOS signing | Manual provisioning | `match` (Fastlane) or skip with `--no-codesign` | CI doesn't need signing for library |
| GitHub releases | Manual upload | `gh release create` or `softprops/action-gh-release@v1` | Automated, integrates with workflow |
| Changelog parsing | Custom scripts | `conventional-changelog` or manual | Small project, manual is fine |

**Key insight:** The project already has solid CI foundation. The release workflow should extend it, not replace it.

## Common Pitfalls

### Pitfall 1: XCFramework Size Exceeds pub.dev Limits

**What goes wrong:** Including the XCFramework in the package causes publish failure with "Package archive is too large" error.

**Why it happens:** pub.dev limits packages to 100MB compressed. XCFramework with llama.cpp is ~30-40MB.

**How to avoid:**
- Never include XCFramework in pub.dev package
- Host on GitHub Releases
- Download during build/pod install

**Warning signs:** `dart pub publish --dry-run` reports package size > 50MB

### Pitfall 2: Version Mismatch Between pubspec and podspec

**What goes wrong:** Users get wrong native binary version, causing crashes or API mismatches.

**Why it happens:** Manual version updates forget one of the files.

**How to avoid:**
- Single source of truth for version (pubspec.yaml)
- CI script reads version and updates podspec
- Pre-commit hook validates version sync

**Warning signs:** podspec version differs from pubspec version

### Pitfall 3: Static Framework Embedding

**What goes wrong:** App Store rejection with "Found an unexpected Mach-O header code archive" error.

**Why it happens:** XCFramework contains static libraries that get embedded instead of linked.

**How to avoid:**
- Use `static_framework = true` in podspec (already set)
- Use `-force_load` linker flags (already configured)
- Never set "Embed & Sign" for static libraries in Xcode

**Warning signs:** Binary inspection shows static library embedded in app bundle

### Pitfall 4: Symbol Stripping Breaks FFI

**What goes wrong:** "Failed to lookup symbol" error at runtime after release build.

**Why it happens:** Xcode strips symbols needed for FFI `dlsym` lookups.

**How to avoid:**
- Use `-exported_symbol` linker flags (already in podspec)
- Set Strip Style to "Non-Global Symbols" in Xcode
- Verify symbols present with `nm` after build

**Warning signs:** Works in debug, fails in release

### Pitfall 5: Missing pub.dev Documentation

**What goes wrong:** Low pub.dev score, poor discoverability.

**Why it happens:** README not optimized for pub.dev display, missing example.

**How to avoid:**
- Ensure example/ directory has runnable code
- Document 20%+ of public API
- Include usage example at top of README

**Warning signs:** pana score < 130 points

### Pitfall 6: prepare_command Doesn't Run from pub.dev

**What goes wrong:** XCFramework not downloaded when package installed from pub.dev.

**Why it happens:** CocoaPods `prepare_command` only runs for local (`:path`) pods, not published ones.

**How to avoid:**
- Use `s.source = { :http => 'url' }` with `vendored_frameworks`
- OR use Dart Native Assets approach
- Test by installing from pub.dev, not local path

**Warning signs:** Works locally with `path: ../`, fails from `pub get`

## Code Examples

### pub.dev Publishing Workflow

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-xcframework:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Build XCFramework
        run: ./scripts/build-ios.sh --clean --release

      - name: Create Release Archive
        run: |
          cd flutter/ios/Frameworks
          zip -r EdgeVedaCore-ios.xcframework.zip EdgeVedaCore.xcframework

      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: flutter/ios/Frameworks/EdgeVedaCore-ios.xcframework.zip

  publish-pub:
    needs: build-xcframework
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'

      - name: Validate Package
        working-directory: flutter
        run: |
          flutter pub get
          dart pub publish --dry-run

      - name: Publish to pub.dev
        working-directory: flutter
        run: dart pub publish --force
        env:
          PUB_TOKEN: ${{ secrets.PUB_TOKEN }}
```

### Pre-publish Validation Script

```bash
#!/bin/bash
# scripts/prepare-release.sh

set -e

VERSION=$1
if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/prepare-release.sh 1.0.0"
  exit 1
fi

echo "Preparing release v$VERSION..."

# Update pubspec.yaml version
sed -i '' "s/^version: .*/version: $VERSION/" flutter/pubspec.yaml

# Update podspec version
sed -i '' "s/s.version          = '.*/s.version          = '$VERSION'/" flutter/ios/edge_veda.podspec

# Verify versions match
PUBSPEC_VERSION=$(grep "^version:" flutter/pubspec.yaml | cut -d' ' -f2)
PODSPEC_VERSION=$(grep "s.version" flutter/ios/edge_veda.podspec | sed "s/.*'\(.*\)'/\1/")

if [ "$PUBSPEC_VERSION" != "$PODSPEC_VERSION" ]; then
  echo "ERROR: Version mismatch - pubspec: $PUBSPEC_VERSION, podspec: $PODSPEC_VERSION"
  exit 1
fi

# Run pana to check score
cd flutter
flutter pub get
dart pub global activate pana
dart pub global run pana --no-warning .

echo "Ready to release v$VERSION"
echo "Next steps:"
echo "  1. Update CHANGELOG.md"
echo "  2. git add -A && git commit -m 'chore: prepare release v$VERSION'"
echo "  3. git tag v$VERSION"
echo "  4. git push && git push --tags"
```

### Podspec with HTTP Source for XCFramework

```ruby
# flutter/ios/edge_veda.podspec
Pod::Spec.new do |s|
  s.name             = 'edge_veda'
  s.version          = '1.0.0'
  s.summary          = 'Edge Veda SDK - On-device AI inference for Flutter'
  s.homepage         = 'https://github.com/edgeveda/edge-veda-sdk'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Edge Veda' => 'contact@edgeveda.com' }

  # Source the Flutter plugin code
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.static_framework = true

  s.dependency 'Flutter'

  # XCFramework downloaded separately - not included in pod
  # Users must either:
  # 1. Use Dart Native Assets (automatic)
  # 2. Run build-ios.sh manually
  s.preserve_paths = 'Frameworks/EdgeVedaCore.xcframework'

  s.frameworks = 'Metal', 'MetalPerformanceShaders', 'Accelerate'
  s.libraries = 'c++'

  # Force-load static library and export symbols for FFI
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => [
      '-force_load "${PODS_ROOT}/../.symlinks/plugins/edge_veda/ios/Frameworks/EdgeVedaCore.xcframework/ios-arm64/libedge_veda_full.a"',
      # ... existing symbol exports ...
    ].join(' ')
  }
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Include binary in package | Host binary externally, download at build | Always for large binaries | Required for pub.dev compliance |
| OS-specific build files | Dart Native Assets (`hook/build.dart`) | Flutter 3.38 (Nov 2025) | Simpler cross-platform native code |
| Manual `dlopen()` paths | `@Native() external` with auto-resolution | Dart 3.0 | Cleaner FFI, cross-platform |
| vendored_frameworks in package | HTTP source or Native Assets | N/A | Size limit compliance |

**Deprecated/outdated:**
- Including xcframeworks directly in pub.dev package (size limits)
- Bitcode (Apple deprecated in Xcode 14)
- i386 architecture (dropped from iOS simulators)

## Open Questions

### 1. Dart Native Assets for iOS XCFramework Download

**What we know:**
- Dart Native Assets is stable in Flutter 3.38
- It supports downloading pre-built binaries
- Examples exist for simple cases

**What's unclear:**
- Exact implementation for XCFramework download and linking
- How it interacts with existing podspec configuration
- Whether force_load flags need adjustment

**Recommendation:** Start with Option B (podspec HTTP source) for v1.0.0 as it's well-understood, then migrate to Dart Native Assets for v1.1.0 after more community examples emerge.

### 2. pub.dev Token for CI Publishing

**What we know:**
- `dart pub publish` requires authentication
- Can use `PUB_TOKEN` environment variable
- Token generated from pub.dev account

**What's unclear:**
- Token rotation policy
- Best practices for team access

**Recommendation:** Generate token from project owner account, store as GitHub secret, document refresh process.

### 3. Simulator Slice in XCFramework

**What we know:**
- XCFramework includes both device (arm64) and simulator (arm64) slices
- Some App Store validation issues reported with simulator slices
- Build script already creates both

**What's unclear:**
- Whether to include simulator slice in release XCFramework
- Impact on development workflow if omitted

**Recommendation:** Include simulator slice. The validation issues are for embedding, not linking static frameworks. Test with `flutter build ipa` before release.

## Sources

### Primary (HIGH confidence)

- [Dart Publishing Packages](https://dart.dev/tools/pub/publishing) - Official pub.dev requirements, size limits, file requirements
- [Flutter Developing Packages](https://docs.flutter.dev/packages-and-plugins/developing-packages) - Plugin structure, podspec configuration, publishing
- [Flutter FFI/Native Code Binding](https://docs.flutter.dev/platform-integration/bind-native-code) - Dart Native Assets, hook/build.dart, cross-platform native code
- [pub.dev Scoring](https://pub.dev/help/scoring) - Pana scoring breakdown, requirements for max points
- [CocoaPods Podspec Reference](https://guides.cocoapods.org/syntax/podspec.html) - prepare_command, vendored_frameworks, HTTP source

### Secondary (MEDIUM confidence)

- [llama.cpp XCFramework PR #11996](https://github.com/ggml-org/llama.cpp/pull/11996) - CMake configuration for iOS/simulator XCFramework build
- [Flutter GitHub Actions CI/CD](https://blog.logrocket.com/flutter-ci-cd-using-github-actions/) - Workflow patterns, Flutter action usage
- [tflite_flutter Package](https://pub.dev/packages/tflite_flutter) - Example of Flutter plugin with native binary (symbol stripping workaround)

### Tertiary (LOW confidence)

- [Flutter Issue #149168](https://github.com/flutter/flutter/issues/149168) - XCFramework integration challenges (known issues, no official solution)
- [llamadart Package](https://pub.dev/packages/llamadart) - Example of Dart Native Assets for binary download (newer approach)
- Various Medium articles on Flutter CI/CD - Patterns confirmed but not officially documented

## Metadata

**Confidence breakdown:**
- Publishing requirements: HIGH - Official Dart documentation verified
- XCFramework distribution: MEDIUM - Multiple approaches documented, but edge cases unclear
- CI/CD workflow: HIGH - Project already has working CI, release extension is straightforward
- Pana scoring: HIGH - Official documentation clear
- Dart Native Assets: MEDIUM - Official but new, fewer community examples

**Research date:** 2026-02-04
**Valid until:** 2026-03-04 (30 days - stable domain, official docs referenced)

---

## Existing Project Assets

The project already has these release-ready components:

| Component | Status | Location |
|-----------|--------|----------|
| pubspec.yaml | Ready | `flutter/pubspec.yaml` - valid metadata, version 1.0.0 |
| README.md | Ready | `flutter/README.md` - comprehensive, 376 lines |
| CHANGELOG.md | Ready | `flutter/CHANGELOG.md` - follows Keep a Changelog format |
| LICENSE | Ready | `flutter/LICENSE` - MIT license |
| Example app | Ready | `flutter/example/` - working chat app with benchmarks |
| Podspec | Needs update | `flutter/ios/edge_veda.podspec` - version mismatch (0.1.0 vs 1.0.0) |
| Build script | Ready | `scripts/build-ios.sh` - creates XCFramework |
| CI workflow | Partial | `.github/workflows/ci.yml` - tests only, needs release job |
| XCFramework | Built | `flutter/ios/Frameworks/EdgeVedaCore.xcframework` - gitignored, build artifact |

**Immediate fixes needed:**
1. Sync podspec version to 1.0.0
2. Add release workflow to CI
3. Decide XCFramework distribution approach
4. Generate pub.dev token
