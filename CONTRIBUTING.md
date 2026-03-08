# Contributing to Edge Veda

Thank you for considering contributing to Edge Veda! Whether you're fixing a typo, improving docs, or building a whole new platform SDK — every contribution matters.

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Contribution Workflow](#contribution-workflow)
- [Testing Requirements](#testing-requirements)
- [Documentation-Only Contributions](#documentation-only-contributions)
- [Example App Contributions](#example-app-contributions)
- [Core C++ Engine Contributions](#core-c-engine-contributions)
- [Code Contributions](#code-contributions)
- [Branch Naming](#branch-naming)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Development Setup](#development-setup)

---

## Ways to Contribute

| Type | Difficulty | Good First Issue? | Section |
|------|-----------|-------------------|---------|
| Fix typos / improve docs | Easy | Yes | [Docs](#documentation-only-contributions) |
| Build example apps | Easy-Medium | Yes | [Examples](#example-app-contributions) |
| Add usage examples | Easy | Yes | [Docs](#documentation-only-contributions) |
| Write tests | Easy-Medium | Yes | [Code](#code-contributions) |
| Fix bugs | Medium | Sometimes | [Code](#code-contributions) |
| Core C++ engine work | Hard | No | [Core](#core-c-engine-contributions) |
| Add platform support | Hard | No | [Code](#code-contributions) |
| Build new SDK bindings | Hard | No | [Code](#code-contributions) |

Check out our [roadmap tracking issue](https://github.com/ramanujammv1988/edge-veda/issues/23) to see what's planned and where help is needed.

---

## Contribution Workflow

```
1. Find an issue (or create one)
         │
2. Comment "I'd like to work on this"
         │
3. Get assigned by a maintainer
         │
4. Fork repo → create branch
         │
5. Make changes → commit (reference issue)
         │
6. Open PR with "Closes #<issue>" in body
         │
7. CI passes → maintainer reviews
         │
8. Approved → merged → issue auto-closes
```

### Rules

- **Claim before working.** Comment on the issue first to avoid duplicate effort. If there's no activity for 2 weeks, the issue may be unassigned.
- **One issue = one PR.** Keep PRs focused. Large issues can be split into multiple PRs.
- **CI must pass.** Don't request review until checks are green.
- **One approval required.** At least one maintainer must approve before merge.

---

## Testing Requirements

<<<<<<< Updated upstream
| Tier | Scope | Evidence Required |
|------|-------|-------------------|
| **Smoke** | UI, docs, config, strings | `flutter test` + `dart analyze` output |
| **Standard** | Features, bug fixes, audio/STT/TTS | Smoke + 10 min device test session |
| **Core** | Inference, FFI, Scheduler, Isolate workers, memory | Standard + 35 min device session + A/B comparison |
=======
**Every PR that touches code must pass all testing gates before review.** This applies to Dart, native (Swift/Obj-C/Kotlin), and C++ changes. Documentation-only PRs are exempt.
>>>>>>> Stashed changes

### Gate 1: Unit Tests (required for all code PRs)

```bash
cd flutter
flutter test
flutter analyze
```

All existing tests must pass. If you added new functionality, add corresponding tests in `flutter/test/`.

Existing test coverage includes:
- `budget_test.dart` — Budget constraint validation
- `latency_tracker_test.dart` — p50/p95/p99 percentile computation
- `runtime_policy_test.dart` — QoS escalation/restoration
- `memory_estimator_test.dart` — Memory estimation
- `schema_validator_test.dart` — Tool call schema validation

### Gate 2: 30-Minute Soak Test (required for inference, vision, scheduler, telemetry, or memory changes)

The soak test runs continuous vision inference for 30 minutes on a physical device with the camera/screen capture active, validating stability, memory, thermals, and latency under sustained load.

#### How to run

1. **Build and launch the example app:**
   ```bash
   # macOS
   cd flutter/example && flutter run -d macos

   # iOS (physical device only — no simulator)
   cd flutter/example && flutter run --release
   ```

2. **Navigate to the Soak Test tab** in the example app.

3. **Select mode:**
   - **Managed** (default) — Uses the adaptive scheduler with budget enforcement. Use this for most testing.
   - **Raw (Baseline)** — Fixed parameters (2 FPS, 640px, 100 tokens), no QoS adaptation. Use to benchmark raw device capability.

4. **Ensure vision is active:**
   - **macOS:** Screen capture starts automatically (~0.7 FPS).
   - **iOS/Android:** Camera preview should be visible and capturing frames.

5. **Start the test.** Let it run for the full **30 minutes** uninterrupted. Keep the device plugged in or note starting battery level.

6. **Monitor live metrics** on the soak test dashboard:
   - Frames processed, throughput (frames/min)
   - p95 latency, mean latency
   - Thermal state, battery level, RSS memory
   - Budget violations (actionable + observe-only)
   - QoS level (full → reduced → minimal → paused)

#### Pass criteria

| Metric | Threshold |
|--------|-----------|
| Crashes | 0 |
| Model reloads | 0 |
| Thermal peak | Must recover (not stuck at critical) |
| Memory (RSS) | Stable — no sustained upward drift over 30 min |
| p95 latency | Within 1.5x of measured baseline (managed mode) |
| Jetsam kills | 0 |

### Gate 3: Export Telemetry and Update Benchmarks (required for performance-impacting changes)

If your change affects inference speed, memory usage, vision pipeline, scheduler, or GPU utilization, you must export the soak test trace and update `BENCHMARKS.md`.

#### Step 1: Export the JSONL trace

After the soak test completes, tap **"Export Trace"** in the soak test screen. This saves a `.jsonl` file with per-frame telemetry.

The trace file is named: `soak_<mode>_<timestamp>.jsonl`
Example: `soak_managed_20260224T004905.jsonl`

Each line contains one event:
```json
{
  "frame_id": 42,
  "ts_ms": 1771894145239,
  "stage": "total_inference",
  "value": 1523.0,
  "mode": "managed",
  "prompt_tokens": 80,
  "generated_tokens": 54
}
```

Stages recorded per frame: `image_encode`, `prompt_eval`, `decode`, `total_inference`, `rss_bytes`, `thermal_state`, `battery_level`, `available_memory`.

#### Step 2: Derive p95/p99 from the trace

Use the analysis tool to compute percentiles and generate charts:

```bash
python3 tools/analyze_trace.py soak_managed_<timestamp>.jsonl
```

This outputs:
- **p50 / p95 / p99 latencies** (end-to-end frame inference)
- **Throughput** (frames/min in 1-minute sliding windows)
- **Memory trend** (RSS slope over time)
- **Thermal overlay** (state transitions)
- **Token metrics** (total tokens, tokens/sec)

#### Percentile methodology (nearest-rank)

All p50/p95/p99 values use the nearest-rank method:

1. Collect all `total_inference` stage values from the trace
2. **Exclude the first 3 frames** (Metal shader compilation warm-up)
3. Sort the remaining N latencies ascending
4. Compute:
   - `p50 = latencies[floor(0.50 × N)]`
   - `p95 = latencies[floor(0.95 × N)]`
   - `p99 = latencies[floor(0.99 × N)]`

Example (354 frames after warm-up exclusion):
```
p50 = latencies[177] = 1,013 ms
p95 = latencies[336] = 5,912 ms
p99 = latencies[350] = 6,968 ms
```

#### Step 3: Update BENCHMARKS.md

If your numbers differ from the current `BENCHMARKS.md`, update the relevant table:

1. Replace the metrics with your new measurements
2. Note the device, OS version, and model used in the "Test Conditions" section
3. Include the trace filename in your PR so reviewers can verify
4. Add a new entry to `tools/experiments.json` with full run metadata

**Do not remove existing benchmark entries for other platforms** — only update the platform you tested on.

#### Step 4: Attach the trace to your PR

Upload the `.jsonl` file as a PR attachment or commit it to a `traces/` directory if the file is under 1 MB. For larger traces, link to a gist or external upload.

### When to run which gate

| Change type | Gate 1 (unit tests) | Gate 2 (soak test) | Gate 3 (benchmarks) |
|-------------|--------------------|--------------------|---------------------|
| Dart logic, UI, non-inference | Required | Optional | No |
| Inference engine, FFI, C++ core | Required | Required | Required |
| Vision pipeline, VisionWorker | Required | Required | Required |
| Scheduler, budget, QoS, telemetry | Required | Required | Required |
| Memory management | Required | Required | Required |
| Audio/Whisper pipeline | Required | Required (use audio test) | If perf changed |
| Build scripts, CI | Required | Optional | No |
| Documentation only | Not required | Not required | Not required |

---

## Documentation-Only Contributions

**No coding experience required!** Docs contributions are extremely valuable and a great way to get involved.

### What you can work on

- **Fix typos or unclear wording** in README, CONTRIBUTING, or code comments
- **Add usage examples** to the README or `docs/` folder
- **Write API documentation** (dartdoc comments on public functions)
- **Create guides** (getting started, model compatibility, platform-specific notes)
- **Improve inline code comments** where logic is hard to follow

### How to contribute docs (step-by-step)

1. **Fork the repo** on GitHub (click the "Fork" button)

2. **Clone your fork:**
   ```bash
   git clone https://github.com/<your-username>/edge-veda.git
   cd edge-veda
   ```

3. **Create a branch:**
   ```bash
   git checkout -b docs/<short-description>
   # Examples:
   # docs/fix-readme-typos
   # docs/add-getting-started-guide
   # docs/improve-api-comments
   ```

4. **Make your changes.** Common locations:
   - `README.md` — Project overview and quick start
   - `CONTRIBUTING.md` — This file
   - `flutter/lib/src/` — Dart API doc comments (lines starting with `///`)
   - `docs/` — Guides and tutorials (create this folder if needed)
   - `flutter/example/` — Example app code and comments

5. **Commit with a clear message:**
   ```bash
   git add <files-you-changed>
   git commit -m "docs: fix typo in README installation steps"
   ```

6. **Push and open a PR:**
   ```bash
   git push origin docs/<short-description>
   ```
   Then go to GitHub and open a Pull Request. In the PR body, write what you changed and why.

### Tips for docs contributors

- **You don't need to build the project** to fix docs — just edit the files directly.
- **Preview markdown** locally with any markdown viewer, or GitHub will render it in the PR.
- **For API docs**, look at how existing functions are documented and follow the same pattern.
- **When in doubt, ask!** Open an issue or comment on an existing one if you're unsure what to document.

### Docs-related issues

Look for issues labeled [`documentation`](https://github.com/ramanujammv1988/edge-veda/labels/documentation) or [`good first issue`](https://github.com/ramanujammv1988/edge-veda/labels/good%20first%20issue). Issue [#20](https://github.com/ramanujammv1988/edge-veda/issues/20) tracks the main documentation effort.

---

## Example App Contributions

Want to show off what Edge Veda can do? Building example apps is one of the best ways to contribute — it helps new users understand the SDK and showcases real-world use cases.

### What you can build

- **Chat apps** — A simple chat UI powered by an on-device LLM
- **Voice assistant** — Record audio → Whisper transcription → LLM response
- **Image generation** — Text-to-image with Stable Diffusion on-device
- **Summarizer** — Paste or upload text, get an AI summary — all offline
- **Translation** — On-device translation between languages
- **Code assistant** — Local code completion / explanation tool
- **Platform-specific showcases** — Demonstrate macOS menu bar integration, iOS widgets, etc.

### Where example apps live

```
flutter/example/          # The main Flutter example app (iOS + macOS)
examples/                 # Standalone example projects (create if needed)
├── chat_app/             # e.g., minimal chat example
├── voice_assistant/      # e.g., whisper + llm pipeline
└── image_gen/            # e.g., stable diffusion demo
```

### How to contribute an example

1. **Fork and branch:** `git checkout -b examples/<your-app-name>`
2. **Build your example** in `examples/<your-app-name>/`
   - Include a `README.md` explaining what it does and how to run it
   - List which models it works with
   - Keep dependencies minimal
3. **Test it** on at least one platform (iOS or macOS)
4. **Open a PR** with screenshots or a short screen recording

### Guidelines for examples

- **Keep it focused.** Each example should demonstrate one thing well.
- **Use small models.** Examples should work with quantized models (Q4_K_M or smaller) so anyone can run them.
- **Include a README** with setup steps and a screenshot/GIF.
- **Don't duplicate.** Check existing examples first.

---

## Core C++ Engine Contributions

The heart of Edge Veda is its C++ engine wrapping llama.cpp, whisper.cpp, and stable-diffusion.cpp with a unified `ev_*` C API. Contributing here has the highest impact — every SDK and platform benefits.

### What you can work on

- **Performance optimization** — Improve inference speed, reduce memory usage
- **New model format support** — Add support for new GGUF quantization types
- **GPU backends** — Metal improvements, Vulkan support, DirectML
- **Bug fixes** — Memory leaks, crash fixes, edge cases
- **New `ev_*` API functions** — Extend the C API surface for new capabilities
- **Build system** — CMake improvements, new platform targets

### Project structure

```
core/
├── include/           # Public C API headers — the ev_* functions
│   ├── edge_veda.h    # Main header
│   └── ...
├── src/               # Implementation
│   ├── engine.cpp     # Core inference engine
│   ├── bridge.cpp     # C API bridge
│   └── ...
├── third_party/       # llama.cpp, whisper.cpp, stable-diffusion.cpp
└── CMakeLists.txt     # Build configuration
```

### Requirements for core contributions

- **C++17** or later
- **CMake 3.21+**
- Changes must compile on all supported platforms (macOS, iOS — and soon Android, Windows, Linux)
- New `ev_*` functions must follow the existing naming and error-handling conventions
- **No breaking changes** to existing `ev_*` function signatures (we maintain ABI stability)

### Build and test

```bash
# macOS static library
./scripts/build-macos.sh

# iOS XCFramework
./scripts/build-ios.sh

# Run the example app to verify
cd flutter/example && flutter run -d macos
```

---

## Code Contributions

### Development Setup

**Prerequisites:**
- Flutter SDK (3.41+)
- Xcode 15+ (for iOS/macOS)
- CMake 3.21+
- Git

**Getting started:**
```bash
# Clone
git clone https://github.com/<your-username>/edge-veda.git
cd edge-veda

# Run the example app (macOS)
cd flutter/example
flutter run -d macos

# Run tests
cd flutter
flutter test

# Run analyzer
flutter analyze
```

### Project Structure

```
edge-veda/
├── core/              # C++ engine (llama.cpp, whisper.cpp, stable-diffusion)
│   ├── include/       # Public C API headers (ev_* functions)
│   ├── src/           # Implementation
│   └── CMakeLists.txt
├── flutter/           # Flutter plugin
│   ├── lib/src/       # Dart API
│   ├── ios/           # iOS native layer (Obj-C)
│   ├── macos/         # macOS native layer (Swift)
│   ├── android/       # Android native layer (Kotlin) [planned]
│   ├── example/       # Example app
│   └── test/          # Dart tests
└── scripts/           # Build scripts
```

### Code Style

- **Dart:** Follow [Effective Dart](https://dart.dev/effective-dart). Run `flutter analyze` before committing.
- **C++:** Follow the existing code style. Use `clang-format` if available.
- **Swift/Kotlin/Obj-C:** Follow platform conventions.

---

## Branch Naming

Use a prefix that describes the type of change, followed by the issue number:

| Prefix | Use for | Example |
|--------|---------|---------|
| `feat/` | New features | `feat/12-flutter-android` |
| `fix/` | Bug fixes | `fix/25-memory-leak` |
| `docs/` | Documentation only | `docs/fix-readme-typos` |
| `test/` | Adding tests | `test/22-memory-estimator` |
| `ci/` | CI/CD changes | `ci/21-github-actions` |
| `refactor/` | Code refactoring | `refactor/cleanup-ffi-layer` |

---

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <short description>

<optional body>

Refs #<issue-number>
```

**Types:** `feat`, `fix`, `docs`, `test`, `ci`, `refactor`, `chore`

**Examples:**
```
feat(android): add NDK cross-compilation for arm64

Refs #12

docs: add getting started guide for new contributors

fix(macos): correct memory estimation using os_proc_available_memory

Refs #3
```

---

## Pull Request Process

1. Fill out the PR template completely
2. Link the issue using `Closes #<number>` in the PR description
3. Ensure CI checks pass
4. Request review from a maintainer
5. Address review feedback
6. Once approved, a maintainer will merge

**PR title format:** Same as commit messages — `type(scope): description`

---

## Reporting Bugs

Use the [bug report template](https://github.com/ramanujammv1988/edge-veda/issues/new?template=bug_report.md) and include:

- Steps to reproduce
- Expected vs actual behavior
- Platform and version info
- Model being used (if applicable)
- Logs or error output

---

## Questions?

- Open a [GitHub Discussion](https://github.com/ramanujammv1988/edge-veda/discussions) or issue
- Check the [roadmap](https://github.com/ramanujammv1988/edge-veda/issues/23) for project direction
