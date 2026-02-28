# Requirements: Edge Veda v1.1

**Defined:** 2026-02-28
**Core Value:** Zero-cloud, on-device AI for Flutter applications

## v1.1 Requirements

### CI/CD Pipeline (#21, #49)

- [ ] **CICD-01**: NDK version is consistent across ci.yml, build-android.sh, and build.gradle (currently r26c vs r27c)
- [ ] **CICD-02**: Platform builds (iOS, Android) are clearly labeled as optional non-blocking lanes with descriptive names
- [ ] **CICD-03**: CI workflow documentation defines which checks are required vs optional and why
- [ ] **CICD-04**: Integration tests execute on main branch merges with Flutter integration_test package

### Test Suite (#22)

- [ ] **TEST-01**: Dart unit tests cover core functionality with mocked FFI calls (model loading, memory estimation, streaming)
- [ ] **TEST-02**: C++ core tests run and pass via ctest on both Ubuntu and macOS in CI
- [ ] **TEST-03**: Flutter test coverage is uploaded to Codecov and visible on PRs
- [ ] **TEST-04**: Test runner scripts are documented for local development (how to run tests locally)

### Release Infrastructure (#46)

- [ ] **RLSE-01**: prepare-release.sh validates artifact name consistency between podspec URL and release workflow
- [ ] **RLSE-02**: Dry-run release validation passes without actual publishing

## v1.2 Requirements (Deferred)

### Developer Experience (#47, #48, #50, #51)
- **DX-01**: Tiered Dart exports (edge_veda.dart, supervision.dart, primitives.dart)
- **DX-02**: Baseline latency/token metrics in GenerateResponse
- **DX-03**: Preflight canRun guard with actionable memory errors
- **DX-04**: Default runtime supervision in init path

## Out of Scope

| Feature | Reason |
|---------|--------|
| Android Vulkan GPU | Deferred to v1.2+ — requires device testing infrastructure |
| Native SDKs (Swift/Kotlin) | v2.0 scope — requires separate distribution channels |
| Flutter Web (Wasm) | High complexity, experimental — v2.0+ |
| PR size labeling | Nice-to-have, not required for quality gates |
| Changelog generation from conventional commits | Can be manual for now |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CICD-01 | Phase 5 | Pending |
| CICD-02 | Phase 5 | Pending |
| CICD-03 | Phase 5 | Pending |
| CICD-04 | Phase 5 | Pending |
| TEST-01 | Phase 5 | Pending |
| TEST-02 | Phase 5 | Pending |
| TEST-03 | Phase 5 | Pending |
| TEST-04 | Phase 5 | Pending |
| RLSE-01 | Phase 6 | Pending |
| RLSE-02 | Phase 6 | Pending |

**Coverage:**
- v1.1 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0
- Coverage: 100%

---
*Requirements defined: 2026-02-28*
*Last updated: 2026-02-28 after roadmap creation*
