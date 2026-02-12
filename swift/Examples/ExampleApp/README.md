# Edge Veda Swift Example App

A full SwiftUI demonstration app showcasing the Edge Veda SDK for on-device LLM inference on iOS. This example mirrors the Flutter example app's UI and functionality.

## Features

- **Welcome Screen** — Bold red "V" branding with radial glow, "Get Started" onboarding
- **Chat Tab** — ChatSession-based streaming, persona presets (Assistant/Coder/Creative), metrics bar (TTFT, Speed, Memory), benchmark mode
- **Vision Tab** — Continuous camera scanning with VisionWorker + FrameQueue, AR-style description overlay
- **Settings Tab** — Temperature/Max Tokens sliders, storage overview, model management with delete, device info, about section
- **Model Selection Sheet** — Bottom sheet with device status and available models

## Prerequisites

- **macOS** with Xcode 15+
- **iOS 16.0+** device (iPhone 12 or newer recommended)
- **Swift 5.9+**
- Edge Veda SDK built (see main README)

## Build & Run

### 1. Build Native Libraries

```bash
# From project root
./scripts/build-ios.sh --clean --release
```

### 2. Open in Xcode

The example app files are in `swift/Examples/ExampleApp/`. Add them to an Xcode project with the EdgeVeda Swift package dependency:

```swift
// In Package.swift or Xcode project settings
.package(path: "../..") // Points to edge-veda/swift/
```

### 3. Run on Device

Select your iOS device in Xcode and run. The app will:

1. Download the Llama 3.2 1B model (~650 MB) on first launch
2. Initialize the inference engine with Metal GPU acceleration
3. Present the chat interface for testing

## Architecture

```
ExampleApp/
  ExampleApp.swift           # @main App with TabView navigation
  Theme.swift                # AppTheme color constants (matches Flutter)
  WelcomeView.swift          # Onboarding screen with red "V" branding
  ChatView.swift             # Chat tab with streaming, metrics, benchmark
  VisionView.swift           # Vision tab with camera + VisionWorker
  SettingsView.swift         # Settings with sliders, models, device info
  ModelSelectionSheet.swift  # Model list sheet with download status
  README.md                  # This file
```

## Theme

The app uses a true black (`#000000`) background with teal/cyan (`#00BCD4`) accent palette, matching the Flutter example exactly:

| Color | Hex | Usage |
|-------|-----|-------|
| Background | `#000000` | True black |
| Surface | `#0A0A0F` | Cards/surfaces |
| Accent | `#00BCD4` | Teal primary |
| Brand Red | `#E50914` | "V" logo |
| Text Primary | `#F5F5F5` | Near-white |
| User Bubble | `#00838F` | Teal-tinted |

## SDK Version

- **SDK:** 1.1.0
- **iOS Target:** 16.0+
- **Backend:** Metal GPU