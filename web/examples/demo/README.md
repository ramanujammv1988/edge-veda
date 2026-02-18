# Edge Veda Web Demo

A comprehensive demo showcasing the full capabilities of the Edge Veda Web SDK. Loads a GGUF model via WASM and demonstrates all major SDK features: Chat, Voice/STT, Tool Calling, RAG/Document Q&A, Vision, and Benchmarking.

## Features

### 🗨️ **Chat Tab**
- Streaming text generation with token-by-token display
- Real-time performance metrics:
  - **TTFT** (Time To First Token)
  - **Speed** (tokens/second)
  - **Memory Usage** (WASM heap)
  - **Confidence Scoring** (from StreamChunk.confidence)
- Three persona presets:
  - **Assistant** — General-purpose helpful responses
  - **Coder** — Code-focused with examples
  - **Creative** — Imaginative writing
- Context window tracking (2048 tokens)
- Temperature & max tokens controls
- Chat history with 20-message context retention
- Llama 3 Instruct chat template formatting

### 🎤 **Voice/STT Tab**
- Microphone recording via MediaRecorder API
- Speech-to-text transcription using WhisperWorker
- Real-time status updates (Recording → Processing → Transcribed)
- Audio chunk management
- Demo fallback when Whisper not available

### 🔧 **Tools Tab**
- Function calling with ToolRegistry
- Two demo tools:
  - **get_time(location)** — Returns current date/time for a location
  - **calculate(expression)** — Evaluates math expressions
- Real-time tool call/result display
- JSON Schema validation via SchemaValidator
- GBNF grammar-based constrained decoding via GbnfBuilder
- Tool execution flow visualization
- Demo mode fallback for tool responses

### 📚 **RAG Tab**
- Document upload and processing
- Text chunking (500 char chunks, 50 char overlap — matches Flutter SDK)
- Vector embeddings via RagPipeline.withModels()
- 384-dimensional vector search with VectorIndex
- Cosine similarity-based retrieval (top 3 chunks)
- Context-augmented generation
- Document metadata display (filename, chunk count)
- Demo fallback when embeddings unavailable

### 📷 **Vision Tab**
- WebRTC camera access
- Live video stream display
- Camera controls (start/stop)
- Foundation for VisionWorker integration
- Placeholder for image analysis features

### ⚡ **Benchmark Tab**
- Performance testing with 10 iterations (matches Flutter example)
- Metrics tracked per run:
  - Time To First Token (TTFT)
  - Total generation time
  - Token count
  - Tokens per second
- Aggregate statistics (average TTFT, average tok/s)
- Modal display with progress tracking
- Fixed test prompt for consistency

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

## How It Works

### 1. SDK Import & Initialization
```javascript
SDK = await import('../../src/index.js');
edgeVeda = new EdgeVeda({
  modelId: 'llama-3.2-1b-q4_k_m',
  device: 'auto',
  precision: 'q4',
  maxContextLength: 2048,
  enableCache: true,
  numThreads: navigator.hardwareConcurrency || 4,
});
await edgeVeda.init();
```

### 2. Model Download & Caching
- Downloads `Llama-3.2-1B-Instruct-Q4_K_M.gguf` (~750 MB) from HuggingFace
- Progress tracking with bandwidth estimation and ETA
- Retry with exponential backoff on failure
- IndexedDB storage via `model-cache.ts`
- Subsequent visits load instantly from cache

### 3. Chat with Streaming
```javascript
for await (const chunk of edgeVeda.generateStream({
  prompt: buildPrompt(userMessage),
  maxTokens: 256,
  temperature: 0.7,
})) {
  if (chunk.token) {
    accumulated += chunk.token;
    if (chunk.confidence != null) {
      totalConfidence += chunk.confidence;
    }
  }
  if (chunk.done) break;
}
```

### 4. Tool Calling
```javascript
toolRegistry = new SDK.ToolRegistry([
  new SDK.ToolDefinition({
    name: 'get_time',
    description: 'Get current date/time for a location',
    parameters: { /* JSON Schema */ }
  })
]);

const response = await chatSession.sendWithTools(
  prompt,
  (toolCall) => handleToolCall(toolCall),
  { maxTokens: 256 }
);
```

### 5. RAG Pipeline
```javascript
// Load and chunk document
const chunks = chunkText(text); // 500 chars, 50 overlap

// Initialize embedder
ragPipeline = await SDK.RagPipeline.withModels();
vectorIndex = new SDK.VectorIndex(384);

// Embed and index
for (const chunk of chunks) {
  const embedding = await ragPipeline.embed(chunk);
  vectorIndex.add(embedding, chunk);
}

// Search and generate
const queryEmbedding = await ragPipeline.embed(query);
const results = vectorIndex.search(queryEmbedding, 3);
const context = results.map(r => r.content).join('\n\n');
```

### 6. Voice Recording & Transcription
```javascript
// Record audio
const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
mediaRecorder = new MediaRecorder(stream);
mediaRecorder.start();

// Transcribe
whisperWorker = new SDK.WhisperWorker();
await whisperWorker.init();
const result = await whisperWorker.transcribe(audioBlob);
```

## Architecture

```
demo/
  index.html    # Full SPA markup — 5 tabs + modals
  styles.css    # Premium dark theme
  app.js        # SDK integration — all features
  README.md     # Documentation
```

### Key SDK Integration Points

| Feature | SDK API Used | Purpose |
|---------|-------------|---------|
| **Engine Init** | `EdgeVeda.init()` | Spawn Worker, load WASM, copy model |
| **Chat Session** | `ChatSession(edgeVeda, preset)` | Multi-turn conversation management |
| **Streaming** | `edgeVeda.generateStream()` | Async generator yielding StreamChunk |
| **Tool Registry** | `ToolRegistry(tools[])` | Register and manage callable tools |
| **Tool Execution** | `chatSession.sendWithTools()` | Generate with function calling |
| **GBNF Builder** | `GbnfBuilder.fromSchema()` | JSON Schema → GBNF grammar |
| **Schema Validation** | `SchemaValidator.validate()` | Validate tool arguments |
| **RAG Pipeline** | `RagPipeline.withModels()` | Document embedding model |
| **Vector Index** | `VectorIndex(dimensions)` | Cosine similarity search |
| **Whisper STT** | `WhisperWorker.transcribe()` | Speech-to-text |
| **Model Cache** | `getCachedModel(id)` | Check IndexedDB for cached model |
| **Download** | `downloadModelWithRetry()` | Fetch GGUF with progress/retry |
| **Cancel** | `edgeVeda.cancelGeneration()` | Stop mid-generation |
| **Reset** | `edgeVeda.resetContext()` | Clear conversation context |
| **Memory** | `edgeVeda.getMemoryUsage()` | Query WASM heap usage |

## Chat Template (Llama 3 Instruct)

```
<|begin_of_text|><|start_header_id|>system<|end_header_id|>

{system_prompt}<|eot_id|><|start_header_id|>user<|end_header_id|>

{user_message}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

```

System prompts vary by persona:
- **Assistant**: "You are a helpful assistant."
- **Coder**: "You are a coding assistant. Provide clear, working code examples."
- **Creative**: "You are a creative writing assistant. Be imaginative and expressive."

## RAG Chunking Strategy

Matches Flutter SDK implementation:
- **Chunk Size**: 500 characters
- **Overlap**: 50 characters
- **Retrieval**: Top 3 most similar chunks
- **Dimensions**: 384 (MiniLM embeddings)

```javascript
function chunkText(text) {
  const chunkSize = 500;
  const overlap = 50;
  const chunks = [];
  
  let start = 0;
  while (start < text.length) {
    const end = Math.min(start + chunkSize, text.length);
    chunks.push(text.substring(start, end));
    start += chunkSize - overlap;
  }
  
  return chunks;
}
```

## Demo Tools

### get_time(location)
Returns current date, time, and UTC offset for a given location.

**Parameters**:
```json
{
  "location": {
    "type": "string",
    "description": "City or region"
  }
}
```

**Example Call**:
```json
{
  "name": "get_time",
  "arguments": { "location": "New York" }
}
```

**Example Result**:
```json
{
  "local_time": "3:45:30 PM",
  "date": "2/16/2026",
  "location": "New York",
  "utc_offset": "-5"
}
```

### calculate(expression)
Evaluates a mathematical expression.

**Parameters**:
```json
{
  "expression": {
    "type": "string",
    "description": "Math expression"
  }
}
```

**Example Call**:
```json
{
  "name": "calculate",
  "arguments": { "expression": "2 + 2 * 3" }
}
```

**Example Result**:
```json
{
  "result": 8,
  "expression": "2 + 2 * 3"
}
```

## Benchmark Details

Runs 10 iterations with fixed prompt and settings:
- **Prompt**: "Explain quantum computing in one sentence."
- **Max Tokens**: 50
- **Temperature**: 0.7

Tracks per iteration:
- Time To First Token (TTFT) in milliseconds
- Total generation time
- Token count
- Tokens per second

Reports aggregate metrics:
- Average TTFT across successful runs
- Average tokens/second
- Success rate (valid runs / total runs)

## Theme

True black (`#000000`) background with teal/cyan (`#00BCD4`) accent:

| Color | Hex | Usage |
|-------|-----|-------|
| Background | `#000000` | True black |
| Surface | `#0A0A0F` | Cards/surfaces |
| Border | `#1A1A2E` | Subtle borders |
| Accent | `#00BCD4` | Teal primary |
| Brand Red | `#E50914` | "V" logo |
| Text Primary | `#F5F5F5` | Near-white |
| Text Secondary | `#B0B0B0` | Muted text |
| User Bubble | `#00838F` | Teal-tinted |
| Assistant Bubble | `#1A1A2E` | Dark surface |
| Success | `#66BB6A` | Green status |
| Warning | `#FFA726` | Orange status |
| Error | `#EF5350` | Red status |

## Browser Support

| Browser | WASM | WebGPU | Threads | MediaRecorder |
|---------|------|--------|---------|---------------|
| Chrome 113+ | ✅ | ✅ | ✅ (with COOP/COEP) | ✅ |
| Edge 113+ | ✅ | ✅ | ✅ | ✅ |
| Firefox 120+ | ✅ | ❌ | ✅ | ✅ |
| Safari 17+ | ✅ | ⚠️ Experimental | ⚠️ Requires headers | ✅ |

## Performance Notes

### With SharedArrayBuffer (multi-threaded):
- TTFT: ~50-100ms
- Speed: ~20-40 tok/s (depends on hardware)
- Memory: ~256-512 MB

### Without SharedArrayBuffer (single-threaded):
- TTFT: ~200-500ms
- Speed: ~5-15 tok/s
- Memory: ~256-512 MB

### WebGPU Acceleration:
When available, provides additional speedup for tensor operations. Detection shown in Settings tab.

## No Build Step Required

This demo is pure HTML/CSS/JS with zero build dependencies. The SDK is loaded via dynamic ESM `import()` from the source tree.

## SDK Version

- **SDK**: 1.1.0
- **Model**: Llama 3.2 1B Instruct Q4_K_M (~750 MB GGUF)
- **Backend**: WebAssembly + WebGPU (when available)
- **Features**: Full parity with Flutter SDK

## Feature Comparison with Flutter SDK

| Feature | Flutter SDK | Web SDK | Demo Implementation |
|---------|-------------|---------|---------------------|
| Chat/Streaming | ✅ | ✅ | ✅ Chat Tab |
| Voice/STT | ✅ | ✅ | ✅ Voice Tab |
| Tool Calling | ✅ | ✅ | ✅ Tools Tab |
| RAG/Vector Search | ✅ | ✅ | ✅ RAG Tab |
| Vision | ✅ | ✅ | ⚠️ Vision Tab (camera only) |
| Confidence Scoring | ✅ | ✅ | ✅ Metrics Bar |
| Benchmarking | ✅ | ✅ | ✅ Benchmark Tab |
| Multi-turn Context | ✅ | ✅ | ✅ 20-message history |
| Persona Presets | ✅ | ✅ | ✅ 3 presets |
| Model Caching | ✅ | ✅ | ✅ IndexedDB |

## License

Same as Edge Veda SDK — See LICENSE file in project root.