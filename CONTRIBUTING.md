# Contributing to Edge Veda

Thank you for considering contributing to Edge Veda! This guide explains how to get involved.

## Getting Started

1. Fork the repo and create your branch from `main`
2. Install dependencies: `flutter pub get`
3. Run tests: `flutter test`
4. Run analysis: `dart analyze`

## Reporting Bugs

Use the [Bug Report](https://github.com/ramanujammv1988/edge-veda/issues/new?template=bug_report.yml) template. Include:
- SDK version and Flutter version
- Platform (iOS, macOS, Android)
- Device model and OS version
- Steps to reproduce
- Logs or stack traces

## Suggesting Features

Use the [Feature Request](https://github.com/ramanujammv1988/edge-veda/issues/new?template=feature_request.yml) template.

## Pull Requests

### Before You Start

- Check existing issues and PRs to avoid duplicate work
- For large changes, open an issue first to discuss the approach

### PR Requirements

All PRs must pass:
- `flutter test` (all tests green)
- `dart analyze` (no issues)
- `dart format --set-exit-if-changed .` (formatted)

### Evidence Tiers

PRs are categorized by risk level. Each tier requires different evidence:

| Tier | Scope | Evidence Required |
|------|-------|-------------------|
| **Smoke** | UI, docs, config, strings | `flutter test` + `dart analyze` output |
| **Standard** | Features, bug fixes, audio/STT/TTS | Smoke + 10 min device test session |
| **Core** | Inference, FFI, Scheduler, Isolate workers, memory | Standard + 30 min device session + A/B comparison |

### Workflow

1. Create a feature branch (never push to `main` directly)
2. Write code and tests
3. Save `flutter test` and `dart analyze` output
4. Open a Draft PR with the tier label
5. A maintainer will review, run device tests, and merge

## Commit Messages

- Use present tense imperative: `fix: resolve STT crash on iPhone 12`
- Prefix with type: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `style:`, `chore:`
- Keep the first line under 72 characters
- Reference issues: `Fixes #42`

## Questions?

Use [GitHub Discussions](https://github.com/ramanujammv1988/edge-veda/discussions) for questions, ideas, and general help.
