---
name: validate-api-consistency
description: Check that all SDK implementations have consistent APIs
allowed-tools: Read, Grep, Glob
---

# Validate API Consistency

Check all SDK implementations for API consistency across platforms.

## Usage
```
/validate-api-consistency
```

## What Gets Checked

### 1. Method Names
All platforms must expose the same methods:
- `init(modelPath, config?)` - Initialize with model
- `generate(prompt)` - Single response generation
- `generateStream(prompt)` - Streaming generation
- `getMemoryUsage()` - Current memory usage
- `unloadModel()` - Release model from memory
- `dispose()` / `close()` - Cleanup

### 2. Parameter Names and Types
| Parameter | Dart | Swift | Kotlin | TypeScript |
|-----------|------|-------|--------|------------|
| modelPath | String | URL | String | string |
| prompt | String | String | String | string |
| config | GenerateOptions? | Config? | Config? | Config? |

### 3. Return Types
| Method | Dart | Swift | Kotlin | TypeScript |
|--------|------|-------|--------|------------|
| generate | Future<String> | async throws String | suspend String | Promise<string> |
| generateStream | Stream<String> | AsyncThrowingStream | Flow<String> | AsyncIterable |

### 4. Error Types
All platforms must define:
- `ModelNotFoundError`
- `OutOfMemoryError`
- `InferenceError`
- `InvalidConfigError`

## Files to Check

```
flutter/lib/edge_veda.dart
swift/Sources/EdgeVeda/EdgeVeda.swift
kotlin/src/main/kotlin/EdgeVeda.kt
react-native/src/index.tsx
web/src/index.ts
```

## Output Format

```
=== API Consistency Report ===

[PASS] Method names consistent across all platforms
[WARN] Parameter 'modelPath' type differs:
       - Swift uses URL, others use String
       - Suggestion: Accept both or document conversion
[FAIL] Missing method 'unloadModel' in:
       - react-native/src/index.tsx
[PASS] Error types consistent

Summary: 2 PASS, 1 WARN, 1 FAIL
```
