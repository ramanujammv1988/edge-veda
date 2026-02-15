# Health Advisor

Confidence-aware health Q&A with cloud handoff banners -- privately query your medical documents on-device.

> Built with [Edge Veda SDK](../../flutter) -- on-device LLM inference for Flutter

<!-- Screenshot placeholder -->
<!-- ![Health Advisor screenshot](screenshot.png) -->

## SDK Features Demonstrated

- **RagPipeline** -- end-to-end retrieval-augmented generation
- **VectorIndex** -- HNSW-based approximate nearest neighbor search
- **embed() / embedBatch()** -- text embedding with batch support
- **ConfidenceInfo** -- per-token confidence scoring with `needsCloudHandoff` flag
- **GenerateOptions** with `confidenceThreshold` -- enable confidence tracking during generation
- **CancelToken** -- cancel in-flight generation
- **ModelManager** -- automatic model download with progress tracking

## Prerequisites

- iOS device (iPhone 12 or later recommended)
- Xcode 26+ with iOS 18+ SDK
- Flutter 3.16+
- ~714 MB free storage for model downloads

## Quick Start

1. Clone the repo and navigate to the example:
   ```bash
   git clone <repo-url>
   cd edge/examples/health_advisor
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```
   Or open `ios/Runner.xcworkspace` in Xcode and run from there.

## Architecture

The app never imports `edge_veda` directly in UI code. All SDK interaction is wrapped behind service classes:

| File | Wraps | Purpose |
|------|-------|---------|
| `lib/services/health_rag_service.dart` | `EdgeVeda`, `RagPipeline`, `VectorIndex`, `ModelManager`, `GenerateOptions` | Two-model RAG with per-token confidence accumulation; exposes `lastConfidence` for UI badges |
| `lib/services/pdf_service.dart` | -- | Extracts text from PDF/TXT/MD files, chunks text at ~500 chars with overlap |

**Key widgets:**
- `ConfidenceBadge` -- color-coded confidence indicator (green/yellow/red)
- `HandoffBanner` -- dismissible banner suggesting cloud consultation when confidence is low
- `MessageBubble` -- chat message with optional confidence metadata

**HealthRagService** tracks per-token confidence during streaming and exposes a `lastConfidence` getter. After generation completes, the UI reads this to render confidence badges on each message and show a handoff banner when `needsCloudHandoff` is true.

## Models

| Model | Size | Purpose |
|-------|------|---------|
| all-MiniLM-L6-v2 | 46 MB | Embedding (384-dim vectors) |
| Llama 3.2 1B | 668 MB | Text generation / Q&A |

Total first-run download: ~714 MB

## Adapting for Your App

1. Replace the path dependency in `pubspec.yaml` with a pub.dev dependency:
   ```yaml
   edge_veda: ^1.0.0
   ```

2. Copy `lib/services/health_rag_service.dart` as a starting point for confidence-aware RAG.

3. Adjust `confidenceThreshold` in `GenerateOptions` to tune handoff sensitivity (default: 0.3).

4. Implement your own handoff logic -- the `needsCloudHandoff` flag indicates the model is uncertain, but what to do about it is up to your app.
