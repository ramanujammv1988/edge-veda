# Edge Veda Mission & Moat Guardrails

_Last updated: 2026-02-25_

## Purpose
This is a living decision filter for product and engineering changes. Use it to prevent local optimizations that weaken the long-term moat.

## Core Mission
Edge Veda is a **managed on-device AI runtime** that makes local AI in mobile apps:
- Predictable under real-world constraints
- Observable and debuggable over long sessions
- Private/offline by default
- Easy for developers to ship via a simple cross-platform SDK

If a change does not strengthen at least one of these outcomes, it is not mission-aligned.

## Moat Pillars (What We Must Compound)
1. **Runtime Supervision, not raw inference wrappers**
- Budgets, scheduler, QoS degradation, memory/thermal/battery adaptation.
- Competitive edge is sustained behavior over time, not single-burst benchmark numbers.

2. **Persistent Workers + Session Stability**
- Keep models/contexts warm and reused where safe.
- Optimize for long-running sessions with low reload churn and graceful degradation.

3. **Offline-First Privacy**
- Local execution by default, no hidden cloud dependency in core runtime.
- Hybrid/cloud is explicit policy, not implicit fallback.

4. **Cross-Platform API Consistency**
- Same mental model and SDK ergonomics on iOS/Android.
- Avoid platform divergence in API semantics unless unavoidable and documented.

5. **Open Model Ecosystem Leverage**
- Build on llama.cpp/whisper.cpp/stable-diffusion.cpp ecosystem velocity.
- Differentiate in runtime management, policy, scheduling, and DX.

6. **Observability as a Product Feature**
- PerfTrace + structured runtime telemetry are first-class.
- Every important policy action should be diagnosable.

## Non-Negotiable Architecture Invariants
1. No UI-thread blocking inference paths in Flutter (use isolates/workers).
2. Memory/thermal/battery pressure must produce graceful policy changes, not crashes.
3. C API thread-safety contracts must be explicit and enforced in code where feasible.
4. Ownership/lifecycle contracts (context vs stream vs worker) must be documented in public headers.
5. Any persistent context introduction must include:
- cleanup path coverage,
- reset semantics,
- memory accounting,
- concurrency safety.
6. No global mutable shared buffers for per-context data in concurrent code paths.

## Guardrails from Issues #24–#27
1. **Issue #24 (Persistent embed context):**
- Performance wins from persistence are valid only if lifecycle/accounting/reset are complete.
- Latency optimization without memory correctness is regression debt.

2. **Issue #25 (Generate vs active stream KV safety):**
- Protect shared KV state with explicit runtime guards, not assumptions about higher SDK layers.

3. **Issue #26 (Static buffer race):**
- Thread-safe C API cannot rely on shared mutable statics for per-call outputs.

4. **Issue #27 (Lock ordering docs):**
- Lock ordering must be documented and mirrored in implementation comments and behavior.

## Change Acceptance Checklist (Use in PR Reviews)
A change should be blocked if any answer is "No".

1. Does this improve or preserve long-session stability?
2. Is runtime behavior under pressure (memory/thermal/battery) unchanged or better?
3. Are concurrency contracts explicit (locks, ownership, cancellation, lifetimes)?
4. Are memory lifecycle paths complete (init, steady-state, cleanup, reset, stats)?
5. Is cross-platform API behavior still consistent for developers?
6. Is observability preserved or improved (traceability of failures/policy actions)?
7. Does this avoid drifting toward cloud dependence for core capabilities?
8. Does it strengthen our differentiated layer (runtime management + DX), not just parity features?

## Anti-Patterns (Reject by Default)
1. Micro-bench optimization that harms sustained stability.
2. Feature additions that bypass scheduler/budget/runtime policy controls.
3. Hidden state-sharing across contexts/streams without explicit synchronization contract.
4. Platform-specific hacks that alter SDK semantics without clear docs and tests.
5. Shipping capabilities without diagnostics or failure explainability.

## Practical Definition of "Moat-Positive"
A change is moat-positive if it does one or more of:
1. Increases sustained reliability under real device constraints.
2. Reduces total developer effort to ship robust on-device AI.
3. Improves policy-controlled quality/latency tradeoffs at runtime.
4. Expands capability while preserving offline privacy and observability.
5. Improves predictable cross-platform behavior.

## Usage
- Reference this file in PR templates/reviews.
- When a tradeoff is unclear, choose the option that compounds runtime supervision, stability, and developer trust.
- Update this document when strategy evolves (do not let old planning snapshots override current shipped reality).
