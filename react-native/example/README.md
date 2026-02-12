# Edge Veda React Native Example App

A full React Native demonstration app showcasing the Edge Veda SDK for on-device LLM inference. This example mirrors the Flutter example app's UI and functionality.

## Features

- **Welcome Screen** — Bold red "V" branding with radial glow (SVG), "Get Started" onboarding
- **Chat Tab** — ChatSession-based streaming, persona presets (Assistant/Coder/Creative), metrics bar (TTFT, Speed, Memory), benchmark mode
- **Vision Tab** — Continuous camera scanning with VisionWorker + FrameQueue, AR-style description overlay
- **Settings Tab** — Temperature/Max Tokens sliders, storage overview, model management with delete, device info, about section
- **Model Selection Sheet** — Modal bottom sheet with device status and available models

## Prerequisites

- **Node.js** 18+
- **React Native CLI** or **Expo** setup
- **iOS:** Xcode 15+, iOS 16+
- **Android:** Android Studio, SDK 24+
- Edge Veda SDK built (see main README)

## Install

```bash
cd edge-veda/react-native/example

# Install dependencies
npm install

# Additional peer dependencies for the example
npm install react-native-svg react-native-vision-camera
```

## Run

```bash
# iOS
npx react-native run-ios --device

# Android
npx react-native run-android
```

The app will:

1. Download the Llama 3.2 1B model (~650 MB) on first launch
2. Initialize the inference engine
3. Present the chat interface for testing

## Architecture

```
example/
  App.tsx                   # Root app with welcome → main flow
  theme.ts                  # AppTheme color constants (matches Flutter)
  MainTabs.tsx              # Bottom tab navigation
  WelcomeScreen.tsx         # Onboarding screen with red "V" branding
  ChatScreen.tsx            # Chat tab with streaming, metrics, benchmark
  VisionScreen.tsx          # Vision tab with camera + VisionWorker
  SettingsScreen.tsx        # Settings with sliders, models, device info
  ModelSelectionSheet.tsx   # Model list sheet with download status
  README.md                 # This file
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

## Dependencies

- `edge-veda` — Edge Veda React Native SDK
- `react-native-svg` — SVG rendering (Welcome screen logo)
- `react-native-vision-camera` — Camera access (Vision tab)

## SDK Version

- **SDK:** 1.1.0
- **React Native:** 0.73+
- **iOS Target:** 16.0+
- **Android Min SDK:** 24