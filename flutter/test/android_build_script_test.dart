import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tests for scripts/build-android.sh and CI integration.
///
/// Validates that the Android build script:
/// 1. Exists and follows iOS/macOS script conventions
/// 2. Targets the same ABIs as build.gradle
/// 3. Uses correct CMake flags matching core/CMakeLists.txt
/// 4. CI workflow references the script (not the Makefile)
/// 5. Output directory structure matches Android jniLibs convention
void main() {
  // Resolve project root: flutter/test/ → flutter/ → project root
  final projectRoot =
      Directory.current.path.endsWith('flutter')
          ? Directory.current.parent.path
          : Directory(
            '${Directory.current.path}/..',
          ).resolveSymbolicLinksSync();

  final scriptFile = File('$projectRoot/scripts/build-android.sh');
  final iosScriptFile = File('$projectRoot/scripts/build-ios.sh');
  final macosScriptFile = File('$projectRoot/scripts/build-macos.sh');

  // =========================================================================
  // 1. Script existence and structure
  // =========================================================================

  group('build-android.sh — existence and structure', () {
    test('script exists at scripts/build-android.sh', () {
      expect(
        scriptFile.existsSync(),
        true,
        reason: 'scripts/build-android.sh must exist',
      );
    });

    test('script starts with bash shebang', () {
      if (!scriptFile.existsSync()) return;
      final firstLine = scriptFile.readAsLinesSync().first;
      expect(firstLine, '#!/bin/bash');
    });

    test('script uses set -e for fail-fast', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('set -e'));
    });

    test('script has usage header comment', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('Usage:'));
    });
  });

  // =========================================================================
  // 2. Convention parity with iOS and macOS scripts
  // =========================================================================

  group('build-android.sh — convention parity with iOS/macOS', () {
    test('all three platform scripts exist', () {
      expect(scriptFile.existsSync(), true);
      expect(iosScriptFile.existsSync(), true);
      expect(macosScriptFile.existsSync(), true);
    });

    test('all scripts start with same shebang + set -e pattern', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final lines = f.readAsLinesSync();
        expect(
          lines[0],
          '#!/bin/bash',
          reason: '${f.path} must start with bash shebang',
        );
        expect(lines[1], 'set -e', reason: '${f.path} must use set -e');
      }
    });

    test('all scripts define SCRIPT_DIR and PROJECT_ROOT', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final content = f.readAsStringSync();
        expect(
          content,
          contains('SCRIPT_DIR='),
          reason: '${f.path} must define SCRIPT_DIR',
        );
        expect(
          content,
          contains('PROJECT_ROOT='),
          reason: '${f.path} must define PROJECT_ROOT',
        );
      }
    });

    test('all scripts support --clean flag', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final content = f.readAsStringSync();
        expect(
          content,
          contains('--clean'),
          reason: '${f.path} must support --clean',
        );
      }
    });

    test('all scripts support --debug and --release flags', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final content = f.readAsStringSync();
        expect(
          content,
          contains('--debug'),
          reason: '${f.path} must support --debug',
        );
        expect(
          content,
          contains('--release'),
          reason: '${f.path} must support --release',
        );
      }
    });

    test('all scripts support -h/--help', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final content = f.readAsStringSync();
        expect(
          content,
          contains('--help'),
          reason: '${f.path} must support --help',
        );
        expect(content, contains('-h'), reason: '${f.path} must support -h');
      }
    });

    test('all scripts have check_tools function', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final content = f.readAsStringSync();
        expect(
          content,
          contains('check_tools'),
          reason: '${f.path} must have check_tools',
        );
      }
    });

    test('all scripts have submodule init check', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final content = f.readAsStringSync();
        expect(
          content,
          contains('git submodule update --init --recursive'),
          reason: '${f.path} must check for submodules',
        );
      }
    });

    test('all scripts print a banner with "Edge Veda" and build type', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final content = f.readAsStringSync();
        expect(
          content,
          contains('Edge Veda'),
          reason: '${f.path} must print Edge Veda banner',
        );
        expect(
          content,
          contains('Build type:'),
          reason: '${f.path} must print build type',
        );
      }
    });

    test('all scripts have symbol verification', () {
      for (final f in [scriptFile, iosScriptFile, macosScriptFile]) {
        if (!f.existsSync()) continue;
        final content = f.readAsStringSync();
        expect(
          content,
          contains('ev_'),
          reason: '${f.path} must verify ev_* symbols',
        );
      }
    });
  });

  // =========================================================================
  // 3. Android-specific: ABI targets match build.gradle
  // =========================================================================

  group('build-android.sh — ABI targets match build.gradle', () {
    test('script defaults to arm64-v8a armeabi-v7a x86_64', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      // The default ABIS variable
      expect(content, contains('arm64-v8a'));
      expect(content, contains('armeabi-v7a'));
      expect(content, contains('x86_64'));
    });

    test('script does not default to x86 (32-bit Intel)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      // Find the ABIS= line and check it doesn't contain bare 'x86'
      final abiLine = content
          .split('\n')
          .firstWhere((l) => l.startsWith('ABIS='), orElse: () => '');
      if (abiLine.isNotEmpty) {
        // x86_64 is fine, but bare x86 at word boundary is not
        final abis =
            abiLine.split('"').length > 1
                ? abiLine.split('"')[1]
                : abiLine.split('=').last;
        final abiList = abis.trim().split(RegExp(r'\s+'));
        expect(
          abiList,
          isNot(contains('x86')),
          reason: 'Script should not include bare x86 (32-bit)',
        );
      }
    });

    test('script supports --abi override flag', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(
        content,
        contains('--abi'),
        reason: 'Script must accept --abi for custom ABI list',
      );
    });

    test('build.gradle and script agree on ABIs', () {
      if (!scriptFile.existsSync()) return;
      final gradleFile = File('$projectRoot/flutter/android/build.gradle');
      if (!gradleFile.existsSync()) return;

      final gradleContent = gradleFile.readAsStringSync();
      final scriptContent = scriptFile.readAsStringSync();

      // Extract ABIs from build.gradle
      final gradleAbiLine = gradleContent
          .split('\n')
          .firstWhere((l) => l.contains('abiFilters'), orElse: () => '');
      final gradleAbis =
          RegExp(
            r"'([^']+)'",
          ).allMatches(gradleAbiLine).map((m) => m.group(1)!).toSet();

      // Verify each gradle ABI is in the script default
      for (final abi in gradleAbis) {
        expect(
          scriptContent,
          contains(abi),
          reason: 'Script must include $abi from build.gradle',
        );
      }
    });
  });

  // =========================================================================
  // 4. Android-specific: CMake flags
  // =========================================================================

  group('build-android.sh — CMake configuration', () {
    test('uses core/cmake/android.toolchain.cmake', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('android.toolchain.cmake'));
    });

    test('sets ANDROID_PLATFORM=android-24', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('android-24'));
    });

    test('sets ANDROID_STL=c++_shared', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('c++_shared'));
    });

    test('builds shared libraries (not static)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('EDGE_VEDA_BUILD_SHARED=ON'));
      expect(content, contains('EDGE_VEDA_BUILD_STATIC=OFF'));
    });

    test('disables Vulkan (CPU-only for initial build)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('EDGE_VEDA_ENABLE_VULKAN=OFF'));
    });

    test('disables OpenMP (not available in NDK r26)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('GGML_OPENMP=OFF'));
    });

    test('does NOT hardcode GGML_NEON (handled in CMakeLists.txt)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      // NEON is set ABI-conditionally in core/CMakeLists.txt, not the script
      expect(
        content,
        isNot(contains('-DGGML_NEON=')),
        reason:
            'GGML_NEON should be set in CMakeLists.txt per-ABI, not in the build script',
      );
    });

    test('does NOT hardcode GGML_LLAMAFILE (handled in CMakeLists.txt)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(
        content,
        isNot(contains('-DGGML_LLAMAFILE=')),
        reason:
            'GGML_LLAMAFILE should be set in CMakeLists.txt per-ABI, not in the build script',
      );
    });

    test('uses Ninja generator', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('-G Ninja'));
    });
  });

  // =========================================================================
  // 5. Android-specific: shared library output
  // =========================================================================

  group('build-android.sh — shared library output', () {
    test('searches for libedge_veda.so (not .a or .framework)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('libedge_veda.so'));
      // Should NOT search for static libs
      expect(content, isNot(contains('libedge_veda.a')));
    });

    test('copies libc++_shared.so from NDK', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('libc++_shared.so'));
    });

    test('maps ABIs to correct NDK triples', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      // These are the NDK sysroot lib directory names
      expect(content, contains('aarch64-linux-android'));
      expect(content, contains('arm-linux-androideabi'));
      expect(content, contains('x86_64-linux-android'));
    });

    test('outputs to jniLibs directory structure', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('jniLibs'));
    });
  });

  // =========================================================================
  // 6. Android-specific: verification checks
  // =========================================================================

  group('build-android.sh — verification', () {
    test('checks ev_* symbol count (>= 20)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('ev_'));
      // Check for the threshold
      final hasThreshold = content.contains('-lt 20');
      expect(
        hasThreshold,
        true,
        reason: 'Script must verify >= 20 ev_* symbols',
      );
    });

    test('checks llama_* symbol count (>= 50)', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('llama_'));
      final hasThreshold = content.contains('-lt 50');
      expect(
        hasThreshold,
        true,
        reason: 'Script must verify >= 50 llama_* symbols',
      );
    });

    test('checks whisper_* symbols', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('whisper_'));
    });

    test('checks file size with warning threshold', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      // Should have a size check with du or stat
      expect(content, contains('SO_SIZE_KB'));
      expect(content, contains('MAX_SIZE_KB'));
    });

    test('uses readelf or nm for symbol inspection', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      // Should support readelf (Linux/CI) and nm (fallback)
      expect(content, contains('readelf'));
      expect(content, contains('nm'));
    });

    test('exits with error on verification failure', () {
      if (!scriptFile.existsSync()) return;
      final content = scriptFile.readAsStringSync();
      expect(content, contains('VERIFICATION_FAILED'));
      expect(content, contains('exit 1'));
    });
  });

  // =========================================================================
  // 7. CI workflow integration
  // =========================================================================

  group('CI workflow — Android build step', () {
    test('ci.yml references build-android.sh (not make build-android)', () {
      final ciFile = File('$projectRoot/.github/workflows/ci.yml');
      if (!ciFile.existsSync()) return;
      final content = ciFile.readAsStringSync();
      expect(
        content,
        contains('./scripts/build-android.sh'),
        reason: 'CI must use build-android.sh, not make build-android',
      );
    });

    test('ci.yml passes --clean --release to the script', () {
      final ciFile = File('$projectRoot/.github/workflows/ci.yml');
      if (!ciFile.existsSync()) return;
      final content = ciFile.readAsStringSync();
      expect(content, contains('build-android.sh --clean --release'));
    });

    test('ci.yml sets ANDROID_NDK_HOME from setup-ndk step', () {
      final ciFile = File('$projectRoot/.github/workflows/ci.yml');
      if (!ciFile.existsSync()) return;
      final content = ciFile.readAsStringSync();
      expect(content, contains('ANDROID_NDK_HOME'));
      expect(content, contains('setup-ndk'));
    });

    test('ci.yml uploads jniLibs artifact (not AAR)', () {
      final ciFile = File('$projectRoot/.github/workflows/ci.yml');
      if (!ciFile.existsSync()) return;
      final content = ciFile.readAsStringSync();
      expect(content, contains('jniLibs'));
    });
  });

  // =========================================================================
  // 8. iOS vs Android build differences
  // =========================================================================

  group('build-android.sh vs build-ios.sh — key differences', () {
    test('Android builds shared libs (.so), iOS builds static libs (.a)', () {
      if (!scriptFile.existsSync() || !iosScriptFile.existsSync()) return;
      final androidContent = scriptFile.readAsStringSync();
      final iosContent = iosScriptFile.readAsStringSync();

      expect(androidContent, contains('BUILD_SHARED=ON'));
      expect(androidContent, contains('BUILD_STATIC=OFF'));
      expect(iosContent, contains('BUILD_SHARED=OFF'));
      expect(iosContent, contains('BUILD_STATIC=ON'));
    });

    test('Android uses NDK toolchain, iOS uses ios.toolchain.cmake', () {
      if (!scriptFile.existsSync() || !iosScriptFile.existsSync()) return;
      final androidContent = scriptFile.readAsStringSync();
      final iosContent = iosScriptFile.readAsStringSync();

      expect(androidContent, contains('android.toolchain.cmake'));
      expect(iosContent, contains('ios.toolchain.cmake'));
    });

    test('Android disables Metal, iOS enables Metal', () {
      if (!scriptFile.existsSync() || !iosScriptFile.existsSync()) return;
      final androidContent = scriptFile.readAsStringSync();
      final iosContent = iosScriptFile.readAsStringSync();

      // Android has no Metal — uses ENABLE_VULKAN instead
      expect(androidContent, contains('ENABLE_VULKAN=OFF'));
      expect(iosContent, contains('ENABLE_METAL=ON'));
    });
  });
}
