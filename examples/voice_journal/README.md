# Voice Journal

Voice journal with speech-to-text, auto-summarization, and semantic search -- record, transcribe, and search your thoughts on-device.

> Built with [Edge Veda SDK](../../flutter) -- on-device LLM inference for Flutter

<!-- Screenshot placeholder -->
<!-- ![Voice Journal screenshot](screenshot.png) -->

## SDK Features Demonstrated

- **WhisperSession** -- streaming speech-to-text with live transcription
- **ChatSession** -- LLM summarization with `reset()` per entry (no context bleed)
- **VectorIndex** + **embed()** -- semantic search over journal entries
- **ModelManager** -- automatic download of 3 models with progress tracking

## Prerequisites

- iOS device with microphone (iPhone 12 or later recommended)
- Xcode 26+ with iOS 18+ SDK
- Flutter 3.16+
- ~830 MB free storage for model downloads

## Quick Start

1. Clone the repo and navigate to the example:
   ```bash
   git clone https://github.com/ramanujammv1988/edge-veda.git
   cd edge-veda/examples/voice_journal
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

The app never imports `edge_veda` directly in UI code. All SDK interaction is wrapped behind service classes, one per concern:

| File | Wraps | Purpose |
|------|-------|---------|
| `lib/services/stt_service.dart` | `WhisperSession`, microphone capture | Streams audio from mic to whisper model, emits live transcript updates |
| `lib/services/summary_service.dart` | `EdgeVeda`, `ChatSession` | Summarizes transcripts and extracts tags; resets session after each entry |
| `lib/services/search_service.dart` | `EdgeVeda`, `VectorIndex` | Embeds journal entries and persists the HNSW index as JSON to disk |
| `lib/services/journal_db.dart` | `sqflite` | SQLite storage for journal entries (transcript, summary, tags, timestamps) |

Three separate `EdgeVeda`/`WhisperSession` instances run independently, one per concern:
- **SttService** streams microphone audio into `WhisperSession` for live transcription
- **SummaryService** uses `ChatSession` with `reset()` after each summarization to prevent context accumulation
- **SearchService** persists the `VectorIndex` as JSON to disk for cross-session search

## Models

| Model | Size | Purpose |
|-------|------|---------|
| whisper-tiny.en | 77 MB | Speech-to-text |
| Llama 3.2 1B | 636 MB | Summarization |
| all-MiniLM-L6-v2 | 46 MB | Semantic search (384-dim vectors) |

Total first-run download: ~759 MB

## Adapting for Your App

1. Replace the path dependency in `pubspec.yaml` with a pub.dev dependency:
   ```yaml
   edge_veda: ^1.0.0
   ```

2. Copy the service files you need -- each is self-contained and can be used independently.

3. For STT: `SttService` is a good starting point. Call `startRecording()`, listen to `onTranscript`, call `stopRecording()`.

4. For semantic search: `SearchService` shows the pattern of embedding + persisting + querying a `VectorIndex`.
