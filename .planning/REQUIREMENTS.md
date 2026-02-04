# Requirements: Edge Veda Flutter iOS SDK v1

**Milestone:** v1.0 - Flutter iOS On-Device LLM Inference
**Target:** Developers can run Llama 3.2 1B on iOS devices via Flutter

---

## Success Criteria

1. **Working inference:** `generate(prompt)` returns coherent text from Llama 3.2 1B
2. **Acceptable performance:** >10 tokens/sec on iPhone 12+ with Metal
3. **Stable memory:** No jetsam kills on 4GB devices (iPhone 11/SE)
4. **Simple integration:** `flutter pub add edge_veda` → working in <30 minutes
5. **Demo proof:** Example app demonstrates text in → text out

---

## Functional Requirements

### R1: Core Inference (Must Have)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| R1.1 | Load GGUF model from file path | `EdgeVeda.create(modelPath)` succeeds with valid GGUF |
| R1.2 | Generate text from prompt | `generate(prompt)` returns non-empty string |
| R1.3 | System prompt support | System prompt affects generation behavior |
| R1.4 | Configurable max tokens | Generation stops at specified token limit |
| R1.5 | Sampling parameters | Temperature, top-p, top-k affect output randomness |

### R2: Model Management (Must Have)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| R2.1 | Download model from URL | `ModelManager.download(url)` retrieves GGUF file |
| R2.2 | Progress reporting | Download emits progress 0-100% |
| R2.3 | Local caching | Re-download skipped if model exists locally |
| R2.4 | Checksum verification | SHA256 mismatch throws `ModelValidationException` |

### R3: Resource Management (Must Have)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| R3.1 | Memory usage tracking | `getMemoryUsage()` returns current bytes used |
| R3.2 | Proper cleanup | `dispose()` frees all native resources |
| R3.3 | Memory pressure handling | SDK responds to iOS memory warnings |

### R4: Error Handling (Must Have)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| R4.1 | Typed exceptions | All errors are typed (not generic Exception) |
| R4.2 | Clear error messages | Exceptions include actionable message text |
| R4.3 | Initialization errors | Bad model path throws `ModelLoadException` |
| R4.4 | Generation errors | OOM during inference throws `GenerationException` |

### R5: GPU Acceleration (Must Have)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| R5.1 | Metal backend enabled | GPU layers > 0 when `useGpu: true` |
| R5.2 | Performance target | >10 tok/sec on A14+ chips (iPhone 12+) |
| R5.3 | Graceful CPU fallback | Works (slower) if Metal unavailable |

---

## Non-Functional Requirements

### Performance

| Metric | Target | Measurement |
|--------|--------|-------------|
| Token generation | >10 tok/sec | Measured on iPhone 12 with Llama 3.2 1B Q4_K_M |
| Time to first token | <2 seconds | From generate() call to first output |
| Model load time | <5 seconds | From create() to ready state |
| Memory ceiling | <1.2 GB | Total SDK memory including model |

### Compatibility

| Requirement | Target |
|-------------|--------|
| iOS version | 13.0+ |
| Flutter version | 3.16.0+ |
| Dart version | 3.2.0+ |
| Architectures | arm64 only |

### Binary Size

| Component | Target |
|-----------|--------|
| XCFramework | <15 MB |
| Total plugin overhead | <20 MB |

---

## Out of Scope (v1)

These are explicitly NOT in v1:

- **Streaming responses** - Deferred to v2
- **Multi-turn chat history** - Deferred to v2
- **Android support** - Deferred to v2
- **Stop sequences** - Low priority
- **Token counting API** - Nice to have, not blocking
- **Multiple simultaneous models** - Not needed for v1
- **Background inference** - iOS restrictions make this complex
- **Cloud fallback** - Violates on-device promise

---

## Constraints

### Technical Constraints

1. **llama.cpp dependency:** Must use llama.cpp as inference engine (no alternatives)
2. **GGUF only:** Only GGUF model format supported (no ONNX, TFLite, etc.)
3. **Foreground only:** Inference must run in foreground (iOS background limits)
4. **Single instance:** One EdgeVeda instance at a time per app

### Resource Constraints

1. **Memory budget:** Hard limit 1.2GB, warning at 900MB
2. **Context window:** Default 2048 tokens (memory-safe)
3. **Thread count:** Default to device cores - 2 (leave headroom)

### Platform Constraints

1. **No bitcode:** llama.cpp incompatible with bitcode
2. **arm64 only:** No 32-bit support
3. **Metal required:** For performance targets (CPU fallback exists but slow)

---

## Dependencies

### External Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| llama.cpp | Pinned commit (verify latest stable) | Inference engine |
| Flutter ffi | ^2.1.0 | Native bindings |
| path_provider | ^2.1.0 | File system paths |
| http | ^1.2.0 | Model download |
| crypto | ^3.0.3 | SHA256 checksum |

### Build Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| CMake | 3.15+ | C++ build |
| Xcode | 15+ | iOS compilation |
| CocoaPods | Latest | iOS package management |

---

## Validation Plan

### Unit Tests
- FFI binding correctness
- Memory management (no leaks)
- Error handling paths

### Integration Tests
- Full inference pipeline
- Model download and caching
- Memory pressure response

### Device Tests (Manual)
- iPhone 11 (4GB RAM) - Memory stability
- iPhone 12 (4GB RAM) - Performance baseline
- iPhone 13 Pro (6GB RAM) - Performance target
- iOS Simulator - Development workflow

### Acceptance Test
- Demo app: User types prompt → sees generated response
- Performance: >10 tok/sec logged in console
- Memory: No crashes after 10 consecutive generations

---

## Traceability

### Requirement to Source

| Requirement | Source |
|-------------|--------|
| R1.* Core Inference | PRD Section 3.1, Research FEATURES.md |
| R2.* Model Management | PRD Section 3.2, User input (download on first use) |
| R3.* Resource Management | Research PITFALLS.md (jetsam prevention) |
| R4.* Error Handling | Research ARCHITECTURE.md |
| R5.* GPU Acceleration | PRD performance targets, Research STACK.md |

### Requirement to Phase (Roadmap Mapping)

| Requirement | Phase | Status |
|-------------|-------|--------|
| R1.1 | Phase 1 | Not started |
| R1.2 | Phase 1 | Not started |
| R1.3 | Phase 1 | Not started |
| R1.4 | Phase 1 | Not started |
| R1.5 | Phase 1 | Not started |
| R2.1 | Phase 2 | Not started |
| R2.2 | Phase 2 | Not started |
| R2.3 | Phase 2 | Not started |
| R2.4 | Phase 2 | Not started |
| R3.1 | Phase 1 | Not started |
| R3.2 | Phase 1 | Not started |
| R3.3 | Phase 2 | Not started |
| R4.1 | Phase 2 | Not started |
| R4.2 | Phase 2 | Not started |
| R4.3 | Phase 1 | Not started |
| R4.4 | Phase 2 | Not started |
| R5.1 | Phase 1 | Not started |
| R5.2 | Phase 1 | Not started |
| R5.3 | Phase 1 | Not started |

**Coverage:** 19/19 requirements mapped (100%)

---

*Requirements derived from project research and user inputs during /gsd:new-project.*
*Traceability updated: 2026-02-04*
