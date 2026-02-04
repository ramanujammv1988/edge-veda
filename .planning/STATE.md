# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-04)

**Core value:** Developers can add on-device LLM inference to their Flutter apps with a simple API - text in, text out, on both iOS and Android.
**Current focus:** v1.1 Android + Streaming

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-02-04 — Milestone v1.1 started

Progress: [░░░░░░░░░░] 0%

## Milestone Summary

**v1.1: Android + Streaming**
- Android support with Vulkan GPU (API 24+)
- Streaming token-by-token responses
- Feature parity with iOS v1.0

## Accumulated Context

### Decisions

Decisions carried from v1.0:
- Flutter-first approach validated (✓ Good)
- iOS before Android validated (✓ Good)
- Download on first use validated (✓ Good)
- Text in/out before streaming validated (✓ Good)
- Llama 3.2 1B model validated (✓ Good)

v1.1 decisions (pending validation):
- Vulkan for Android GPU (API 24+ requirement)
- Long-lived isolate for streaming (enables persistent callbacks)

### Pending Todos

Carried from v1.0:
- Configure PUB_TOKEN secret in GitHub for automated publishing (optional)
- Create GitHub Release with XCFramework when ready (improves user setup)

### Blockers/Concerns

None currently.

**Environment Notes:**
- CMake installed (4.2.3 via Homebrew)
- Flutter SDK available
- Xcode Command Line Tools only (users build XCFramework locally)
- Android NDK not yet verified in dev environment

## Session Continuity

Last session: 2026-02-04
Stopped at: Milestone v1.1 initialization - defining requirements
Resume file: None

---
*Milestone v1.1 started. Next: research and requirements definition.*
