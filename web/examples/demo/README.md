# Edge Veda Web Demo

A demo page that loads a GGUF model via WASM and generates text in the browser. Built as a standalone HTML/CSS/JS single-page application using the Edge Veda Web SDK.

## How It Works

1. **SDK Import** — Dynamically imports the Edge Veda Web SDK (`EdgeVeda`, `ChatSession`, `downloadModelWithRetry`)
2. **Model Download** — Downloads `Llama-3.2-1B-Instruct-Q4_K_M.gguf` (~750 MB) from HuggingFace with progress tracking, retry with exponential backoff, and SHA-256 verification
3. **IndexedDB Cache** — Model is stored in IndexedDB via `model-cache.ts` so subsequent visits load instantly
4. **WASM Init** — Creates an `EdgeVeda` instance which spawns a Web Worker, loads the WASM module (`llama.cpp` compiled to WebAssembly), and copies the GGUF model into WASM memory
5. **Streaming Generation** — Uses `EdgeVeda.generateStream()` with Llama 3 chat template to stream tokens back to the UI in real-time
6. **Demo Fallback** — If the WASM module isn't available (e.g. missing `.wasm` build), falls back to simulated streaming so the UI is always functional

## Quick Start

```bash
# From the demo directory
cd edge-veda/web/examples/demo

# Serve with any static server (needs CORS headers for HuggingFace download)
npx serve .
# or
python3 -m http.server 8080
```

Open `http://localhost:3000` (or `:8080`) in a modern browser.

### Cross-Origin Isolation (for WASM threads)

For best performance, serve with these headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

This enables `SharedArrayBuffer` which allows multi-threaded WASM inference.

## Features

- **Welcome Screen** — Bold red "V" branding (SVG) with radial glow
- **Chat Tab** — Streaming responses via WASM, persona presets (Assistant/Coder/Creative), TTFT/Speed/Memory metrics, context window tracking
- **Vision Tab** — WebRTC camera placeholder (WebGPU required)
- **Settings Tab** — Temperature/Max Tokens sliders, WebGPU detection, about section
- **Model Selection Modal** — Shows cached/available models from IndexedDB

## Architecture

```
demo/
  index.html    # Full SPA markup — welcome, chat, vision, settings, modal
  styles.css    # Premium dark theme (CSS custom properties)
  app.js        # SDK integration — model download, WASM init, generateStream()
  README.md     # This file
```

### Key SDK Integration Points in `app.js`

| Step | SDK API Used | Purpose |
|------|-------------|---------|
| Import | `import('../../src/index.js')` | Dynamic ESM import of Edge Veda |
| Cache check | `getCachedModel(modelId)` | Check IndexedDB for existing model |
| Download | `downloadModelWithRetry(model, {onProgress})` | Fetch GGUF from HuggingFace with retry |
| Init | `new EdgeVeda(config); edgeVeda.init()` | Spawn Worker, load WASM, copy model |
| Chat session | `new ChatSession(edgeVeda, preset)` | Multi-turn conversation management |
| Generate | `edgeVeda.generateStream(options)` | Async generator yielding `StreamChunk` |
| Cancel | `edgeVeda.cancelGeneration()` | Stop mid-generation |
| Reset | `edgeVeda.resetContext()` | Clear conversation context |
| Memory | `edgeVeda.getMemoryUsage()` | Query WASM heap usage |

### Chat Template

Uses Llama 3 instruct format:

```
<|begin_of_text|><|start_header_id|>system<|end_header_id|>

{system_prompt}<|eot_id|><|start_header_id|>user<|end_header_id|>

{user_message}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

```

## Theme

True black (`#000000`) background with teal/cyan (`#00BCD4`) accent:

| Color | Hex | Usage |
|-------|-----|-------|
| Background | `#000000` | True black |
| Surface | `#0A0A0F` | Cards/surfaces |
| Accent | `#00BCD4` | Teal primary |
| Brand Red | `#E50914` | "V" logo |
| Text Primary | `#F5F5F5` | Near-white |
| User Bubble | `#00838F` | Teal-tinted |

## Browser Support

| Browser | WASM | WebGPU | Threads |
|---------|------|--------|---------|
| Chrome 113+ | ✅ | ✅ | ✅ (with COOP/COEP) |
| Edge 113+ | ✅ | ✅ | ✅ |
| Firefox 120+ | ✅ | ❌ | ✅ |
| Safari 17+ | ✅ | ⚠️ Experimental | ⚠️ Requires headers |

## No Build Step Required

This demo is pure HTML/CSS/JS with zero build dependencies. The SDK is loaded via dynamic ESM `import()` from the source tree.

## SDK Version

- **SDK:** 1.1.0
- **Model:** Llama 3.2 1B Instruct Q4_K_M (~750 MB GGUF)
- **Backend:** WebAssembly (+ WebGPU acceleration when available)