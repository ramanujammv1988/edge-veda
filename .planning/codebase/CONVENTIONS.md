# Code Conventions

## Naming

### Files
| Language | Convention | Example |
|----------|------------|---------|
| C/C++ | snake_case | `edge_veda.h`, `memory_guard.cpp` |
| TypeScript | kebab-case | `model-cache.ts`, `wasm-loader.ts` |
| Dart | snake_case | `edge_veda_impl.dart`, `types.dart` |
| Swift | PascalCase | `EdgeVeda.swift`, `FFIBridge.swift` |
| Kotlin | PascalCase | `EdgeVeda.kt`, `NativeBridge.kt` |

### Identifiers
| Language | Classes | Functions | Variables | Constants |
|----------|---------|-----------|-----------|-----------|
| C | `ev_*` structs | `ev_*` functions | snake_case | UPPER_SNAKE |
| C++ | PascalCase | camelCase | camelCase | kPascalCase |
| TypeScript | PascalCase | camelCase | camelCase | UPPER_SNAKE |
| Dart | PascalCase | camelCase | camelCase | UPPER_SNAKE |
| Swift | PascalCase | camelCase | camelCase | camelCase |
| Kotlin | PascalCase | camelCase | camelCase | UPPER_SNAKE |

### API Naming
```typescript
// Good - consistent across SDKs
EdgeVeda.init(config)
EdgeVeda.generate(prompt, options)
EdgeVeda.generateStream(prompt, options)
EdgeVeda.terminate()

// Bad - inconsistent
EdgeVeda.initialize()  // vs init()
EdgeVeda.run()         // vs generate()
EdgeVeda.close()       // vs terminate()
```

## Code Style

### TypeScript/JavaScript
```typescript
// ESLint: @react-native-community/eslint-config
// Prettier: .prettierrc in react-native/
{
  "tabWidth": 2,
  "singleQuote": true,
  "trailingComma": "es5"
}

// Type imports first
import type { EdgeVedaConfig, GenerateOptions } from './types';
import { someFunction } from './utils';

// Explicit return types
async function generate(options: GenerateOptions): Promise<GenerateResult> {
  // ...
}
```

### Dart
```dart
// flutter_lints: ^3.0.0
// 80 character line width
// 2-space indentation

// Type annotations on public APIs
Future<void> init(EdgeVedaConfig config) async {
  // ...
}

// Factory constructors for configs
class EdgeVedaConfig {
  factory EdgeVedaConfig.defaults() => EdgeVedaConfig(
    device: 'auto',
    maxContextLength: 2048,
  );
}
```

### Swift
```swift
// Swift 5.9+ with strict concurrency
// SwiftFormat for formatting

// Actor for thread safety
public actor EdgeVeda {
    public func generate(prompt: String) async throws -> String {
        // ...
    }
}

// Enums for configuration
public enum Backend {
    case auto
    case metal
    case cpu
}
```

### Kotlin
```kotlin
// Kotlin 1.9.22
// ktlint for formatting

// Coroutines for async
suspend fun generate(prompt: String, options: GenerateOptions): String {
    // ...
}

// Flow for streaming
fun generateStream(prompt: String): Flow<String> = flow {
    // ...
}

// Data classes for configs
data class EdgeVedaConfig(
    val modelPath: String,
    val backend: Backend = Backend.AUTO,
    val contextSize: Int = 2048
)
```

### C/C++
```cpp
// C++17 standard
// clang-format for formatting
// Compiler flags: -Wall -Wextra -Wpedantic -Werror

// C API prefix: ev_
ev_error_t ev_init(const ev_config* config, ev_context* ctx);

// Opaque handles
typedef struct ev_context_impl* ev_context;

// Error returns, not exceptions
ev_error_t result = ev_generate(ctx, prompt, params, &output);
if (result != EV_SUCCESS) {
    // handle error
}
```

## Patterns

### Initialization Pattern
All SDKs follow async init with config:

```typescript
// TypeScript
const sdk = new EdgeVeda(config);
await sdk.init();

// Must check init before use
if (!sdk.isInitialized()) {
  throw new Error('Not initialized');
}
```

### Streaming Pattern
AsyncGenerator/Flow for streaming:

```typescript
// TypeScript
async function* generateStream(options): AsyncGenerator<StreamChunk> {
  // yield chunks
}

// Kotlin
fun generateStream(prompt: String): Flow<StreamChunk>

// Swift
func generateStream(prompt: String) -> AsyncStream<StreamChunk>
```

### Resource Cleanup
Explicit termination required:

```typescript
try {
  const result = await sdk.generate(prompt);
} finally {
  await sdk.terminate();
}
```

## Error Handling

### C++ Layer
```cpp
// Error codes enum
typedef enum {
    EV_SUCCESS = 0,
    EV_ERROR_INVALID_PARAM = -1,
    EV_ERROR_OUT_OF_MEMORY = -2,
    // ...
} ev_error_t;

// Error message lookup
const char* ev_error_string(ev_error_t error);
```

### SDK Layer - Wrap to Platform Idiom
```typescript
// TypeScript - Error class with code
class EdgeVedaError extends Error {
  constructor(public code: EdgeVedaErrorCode, message: string) {
    super(message);
  }
}
```

```swift
// Swift - Error enum
public enum EdgeVedaError: Error {
    case invalidParameter(String)
    case outOfMemory
    case modelLoadFailed(String)
}
```

```kotlin
// Kotlin - Exception with code
class EdgeVedaException(
    val code: EdgeVedaErrorCode,
    message: String
) : Exception(message)
```

## Documentation

### Public APIs
All public functions must have JSDoc/KDoc/DocC:

```typescript
/**
 * Generates text from the given prompt
 * @param options - Generation options including prompt and parameters
 * @returns Generated text result with token count and timing
 * @throws EdgeVedaError if not initialized or generation fails
 */
async generate(options: GenerateOptions): Promise<GenerateResult>
```

### C API Headers
```c
/**
 * @brief Initialize Edge Veda context with configuration
 * @param config Configuration structure
 * @param error Optional pointer to receive error code
 * @return Context handle on success, NULL on failure
 */
ev_context ev_init(const ev_config* config, ev_error_t* error);
```

## Module Organization

### Exports
```typescript
// Barrel exports in index files
export * from './types';
export { EdgeVeda } from './EdgeVeda';
export { init, generate, generateStream } from './convenience';

// Default export for main class
export default EdgeVeda;
```

### Internal vs Public
```
src/
├── index.ts          # Public exports only
├── EdgeVeda.ts       # Public class
├── types.ts          # Public types
└── internal/         # Private implementation
    ├── bridge.ts
    └── utils.ts
```
