# Roadmap: Edge Veda

## Milestones

- ✅ **v1.0 Flutter Android Support** — Phases 1-4 (shipped 2026-02-28)
- 🚧 **v1.1 CI/CD + Quality** — Phases 5-6 (in progress)

## Phases

<details>
<summary>✅ v1.0 Flutter Android Support (Phases 1-4) — SHIPPED 2026-02-28</summary>

- [x] Phase 1: Foundation — Build System & Scripts (2/2 plans) — completed 2026-02-28
- [x] Phase 2: Native Android Layer — JNI & Kotlin (2/2 plans) — completed 2026-02-28
- [x] Phase 3: Flutter Plugin Integration — Dart (1/1 plan) — completed 2026-02-28
- [x] Phase 4: Verification Loop (2/2 plans) — completed 2026-02-28

</details>

### 🚧 v1.1 CI/CD + Quality (In Progress)

**Milestone Goal:** Establish CI/CD pipeline, test suite, and release infrastructure to ensure quality gates before further feature expansion.

- [ ] **Phase 5: CI/CD + Testing Infrastructure** - Harden CI pipeline and expand test coverage
- [ ] **Phase 6: Release Validation** - Validate and fix release artifact contracts

## Phase Details

### Phase 5: CI/CD + Testing Infrastructure
**Goal**: CI pipeline is robust with deterministic vs device-only lanes, and test coverage is comprehensive and visible
**Depends on**: Phase 4
**Requirements**: CICD-01, CICD-02, CICD-03, CICD-04, TEST-01, TEST-02, TEST-03, TEST-04
**Success Criteria** (what must be TRUE):
  1. Developer can see which CI checks are required vs optional before pushing code
  2. CI fails predictably when platform builds break, without blocking unrelated changes
  3. Developer can run all tests locally with documented commands matching CI behavior
  4. Code coverage is visible on pull requests with trend information
**Plans**: 3 plans

Plans:
- [ ] 05-01-PLAN.md — Fix NDK consistency, label optional CI jobs, configure Codecov
- [ ] 05-02-PLAN.md — Register C++ tests, create integration smoke test, add streaming unit test
- [ ] 05-03-PLAN.md — CI documentation and local test runner docs

### Phase 6: Release Validation
**Goal**: Release artifacts have validated contracts and dry-run validation prevents broken releases
**Depends on**: Phase 5
**Requirements**: RLSE-01, RLSE-02
**Success Criteria** (what must be TRUE):
  1. Release script fails fast if podspec URL does not match release workflow artifact name
  2. Developer can run dry-run validation locally before creating release PR
**Plans**: TBD

Plans:
- [ ] TBD

## Progress

**Execution Order:**
v1.0 complete → Phase 5 → Phase 6

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation (Build System & Scripts) | v1.0 | 2/2 | Complete | 2026-02-28 |
| 2. Native Android Layer (JNI & Kotlin) | v1.0 | 2/2 | Complete | 2026-02-28 |
| 3. Flutter Plugin Integration (Dart) | v1.0 | 1/1 | Complete | 2026-02-28 |
| 4. Verification Loop | v1.0 | 2/2 | Complete | 2026-02-28 |
| 5. CI/CD + Testing Infrastructure | v1.1 | 0/3 | Planning complete | - |
| 6. Release Validation | v1.1 | 0/TBD | Not started | - |
