# Testing

## Current Status

**No automated tests exist in the codebase.**

This represents significant technical debt for a production SDK.

## Test Infrastructure by Platform

### C++ Core
| Item | Status | Location |
|------|--------|----------|
| Test framework | Not configured | - |
| Test files | None | `core/tests/` (empty) |
| CMake support | Prepared | `EDGE_VEDA_BUILD_TESTS` option |
| Makefile target | Ready | `make test-core` |

**Recommended:** Google Test or Catch2

### Flutter/Dart
| Item | Status | Location |
|------|--------|----------|
| Test framework | Configured | `flutter_test` in pubspec.yaml |
| Test files | None | - |
| Makefile target | Ready | `make test-flutter` |

**Recommended structure:**
```
flutter/test/
├── edge_veda_test.dart
├── model_manager_test.dart
└── ffi/
    └── bindings_test.dart
```

### Swift
| Item | Status | Location |
|------|--------|----------|
| Test framework | Configured | XCTest via SPM |
| Test files | Placeholder | `swift/Tests/EdgeVedaTests/EdgeVedaTests.swift` |
| Makefile target | Ready | `make test-swift` |

### Kotlin/Android
| Item | Status | Location |
|------|--------|----------|
| Test framework | Configured | JUnit 4.13.2, MockK 1.13.8 |
| Test files | None | `kotlin/src/test/kotlin/` (empty) |
| Instrumented tests | Configured | Espresso 3.5.1 |
| Makefile target | Ready | `make test-android` |

**Dependencies configured:**
```kotlin
testImplementation("junit:junit:4.13.2")
testImplementation("io.mockk:mockk:1.13.8")
testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
```

### React Native
| Item | Status | Location |
|------|--------|----------|
| Test framework | Not configured | - |
| Test files | None | - |
| Makefile target | Ready | `make test-rn` |

**Recommended:** Jest with @testing-library/react-native

### Web
| Item | Status | Location |
|------|--------|----------|
| Test framework | Not configured | - |
| Test files | None | - |
| Makefile target | None | - |

**Recommended:** Vitest

## Critical Paths to Test

### 1. Initialization
```typescript
// Must test:
- Config validation (invalid paths, unsupported backends)
- Backend auto-detection
- Memory limit configuration
- Double initialization prevention
```

### 2. Text Generation
```typescript
// Must test:
- Empty prompt handling
- Max token limits
- Stop sequence detection
- Parameter validation (temperature 0-2, top_p 0-1, etc.)
```

### 3. Streaming
```typescript
// Must test:
- Async iteration
- Early cancellation
- Error mid-stream
- Memory cleanup on abort
```

### 4. Memory Management
```typescript
// Must test:
- Memory pressure callbacks
- Auto-unload behavior
- Peak memory tracking
- Cleanup on terminate
```

### 5. Error Handling
```typescript
// Must test:
- All error codes propagate correctly
- Error messages are informative
- Recovery after errors
```

## Mocking Strategy

### Native Modules
```typescript
// React Native - mock TurboModule
jest.mock('./NativeEdgeVeda', () => ({
  initialize: jest.fn(),
  generate: jest.fn(),
  terminate: jest.fn(),
}));

// Flutter - mock FFI
class MockEdgeVedaBindings implements EdgeVedaBindings {
  // mock implementations
}
```

### Platform APIs
| Platform | Mock Targets |
|----------|--------------|
| Web | IndexedDB, fetch, Worker, WebGPU |
| Flutter | path_provider, ffi lookups |
| Swift | FileManager, Metal device |
| Kotlin | Context, JNI library loading |

## Test Commands

```bash
# All tests
make test

# Per-platform
make test-core      # C++ unit tests
make test-flutter   # Flutter unit tests
make test-swift     # Swift package tests
make test-android   # Android unit + instrumented
make test-rn        # React Native tests (when configured)
```

## CI Integration

GitHub Actions workflow exists at `.github/workflows/ci.yml`

**Makefile CI targets:**
```make
ci-test-all:
    make test-core
    make test-flutter
    make test-swift
```

## Recommended Test Implementation Priority

1. **Core C++ tests** - Foundation for all platforms
2. **Swift tests** - iOS is primary mobile target
3. **Kotlin tests** - Android coverage
4. **Web tests** - Browser inference validation
5. **Flutter tests** - Cross-platform plugin
6. **React Native tests** - Bridge layer validation

## Coverage Gaps (Critical)

| Component | Risk | Impact |
|-----------|------|--------|
| C++ engine | High | Core inference correctness |
| Memory guard | High | Crashes, memory leaks |
| FFI bridges | High | Platform-specific crashes |
| Streaming | Medium | User experience |
| Error handling | Medium | Debugging difficulty |
| Model caching | Low | Performance only |
