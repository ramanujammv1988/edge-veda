# Document Q&A

On-device document Q&A powered by RAG -- ask questions about any PDF or text file, 100% offline.

> Built with [Edge Veda SDK](../../flutter) -- on-device LLM inference for Flutter

<!-- Screenshot placeholder -->
<!-- ![Document Q&A screenshot](screenshot.png) -->

## SDK Features Demonstrated

- **RagPipeline** -- end-to-end retrieval-augmented generation (embed, search, generate)
- **VectorIndex** -- HNSW-based approximate nearest neighbor search
- **embed()** -- text embedding with all-MiniLM-L6-v2
- **EdgeVeda** (dual-model) -- separate instances for embedding and generation
- **ModelManager** -- automatic model download with progress tracking
- **Streaming generation** -- real-time token-by-token output via `TokenChunk`

## Prerequisites

- iOS device (iPhone 12 or later recommended)
- Xcode 26+ with iOS 18+ SDK
- Flutter 3.16+
- ~714 MB free storage for model downloads

## Quick Start

1. Clone the repo and navigate to the example:
   ```bash
   git clone <repo-url>
   cd edge/examples/document_qa
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
| `lib/services/rag_service.dart` | `EdgeVeda`, `RagPipeline`, `VectorIndex`, `ModelManager` | Manages two EdgeVeda instances (embedder + generator), downloads models, embeds document chunks, runs RAG queries |
| `lib/services/pdf_service.dart` | -- | Extracts text from PDF/TXT/MD files, chunks text at ~500 chars with overlap |

**RagService** manages two `EdgeVeda` instances: one loaded with the embedding model (all-MiniLM-L6-v2) and one with the generation model (Llama 3.2 1B). When a document is loaded, `PdfService` extracts and chunks the text, then `RagService` embeds each chunk into a `VectorIndex`. Queries go through `RagPipeline.queryStream()` which embeds the query, retrieves relevant chunks, and streams generated answers.

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

2. Copy `lib/services/rag_service.dart` as a starting point for your own RAG service.

3. Customize the chunking strategy in `PdfService.chunkText()` to match your document format.

4. Swap in different models via `ModelRegistry` or register your own GGUF models.
