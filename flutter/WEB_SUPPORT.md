# Edge Veda Web Support (WebAssembly)

Run on-device AI inference directly in the browser via WebAssembly.

## Prerequisites

- [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html) installed
- CMake 3.22+

## Building the WASM Module

```bash
# Activate Emscripten
source /path/to/emsdk/emsdk_env.sh

# Build
./scripts/build-web.sh
```

This produces:
- `flutter/web/wasm/edge_veda.js` — JS glue code
- `flutter/web/wasm/edge_veda.wasm` — WASM binary

## Integration

Add to your Flutter web app's `web/index.html`:

```html
<script src="wasm/edge_veda.js"></script>
```

The WASM inference runs in a Web Worker (`worker.js`) to avoid blocking the UI thread.

## Limitations

- **Memory**: WASM has a ~2 GB memory limit. Use small quantized models only (Q4_0, Q4_K_M).
- **Performance**: Significantly slower than native. SIMD128 helps but no GPU acceleration.
- **Model Loading**: Models are downloaded via `fetch()` and cached in IndexedDB.
- **Threading**: Limited to 4 pthreads via Emscripten's pthread pool.

## Recommended Models for Web

| Model | Size | Use Case |
|-------|------|----------|
| TinyLlama 1.1B Q4_K_M | ~669 MB | Chat |
| Llama 3.2 1B Q4_K_M | ~668 MB | Instruction following |
| Qwen3 0.6B Q4_K_M | ~397 MB | Smallest option |
| Whisper Tiny EN | ~77 MB | Speech-to-text |
| All MiniLM L6 v2 | ~46 MB | Embeddings |

## Architecture

```
Flutter Web App (Dart)
    ↓ dart:js_interop
EdgeVedaWeb (Web Worker communication)
    ↓ postMessage
Web Worker (worker.js)
    ↓ cwrap/ccall
WASM Module (edge_veda.wasm)
    ↓
CPU (SIMD128)
```
